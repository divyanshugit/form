import Foundation
import ImageIO
import UIKit

/// Progress photos: saved on the phone first, uploaded to the private bucket when there's signal.
@MainActor
@Observable
final class PhotoStore {
    /// Newest first.
    private(set) var photos: [ProgressPhoto] = []
    private(set) var pendingCount = 0
    /// Why the last upload attempt failed, shown next to the queue count.
    private(set) var uploadError: String?
    var errorMessage: String?

    private let repository: PhotoRepository
    private let directory: URL
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()
    @ObservationIgnored private var isSyncing = false

    init(repository: PhotoRepository = SupabasePhotoRepository(), directory: URL? = nil) {
        self.repository = repository
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Form/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directory = base
        thumbnails.countLimit = 200
        photos = pending().sorted { $0.takenAt > $1.takenAt }
        pendingCount = pending().count
    }

    var first: ProgressPhoto? { photos.min { $0.takenAt < $1.takenAt } }
    var latest: ProgressPhoto? { photos.first }

    func dayNumber(_ photo: ProgressPhoto) -> Int {
        PhotoTimeline.dayNumber(of: photo, first: first?.takenAt)
    }

    // MARK: Adding

    /// Saves a photo locally (resized JPEG), shows it immediately, then uploads.
    @discardableResult
    func add(_ image: UIImage, takenAt: Date = .now, workoutID: UUID? = nil, bodyWeightKg: Double? = nil) async -> ProgressPhoto? {
        guard let jpeg = Self.jpeg(image) else {
            errorMessage = "Couldn't process that photo."
            return nil
        }
        let id = UUID()
        let folder = repository.userFolder() ?? "local"
        let photo = ProgressPhoto(id: id, workoutId: workoutID, storagePath: "\(folder)/\(id.uuidString.lowercased()).jpg",
                                  takenAt: takenAt, bodyWeightKg: bodyWeightKg)
        do {
            try jpeg.write(to: fileURL(photo.id), options: .atomic)
        } catch {
            errorMessage = "Couldn't save the photo on this phone."
            return nil
        }
        setPending(pending() + [photo])
        photos.append(photo)
        photos.sort { $0.takenAt > $1.takenAt }
        await sync()
        return photo
    }

    func updateWeight(_ photo: ProgressPhoto, kg: Double?) async {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        photos[index].bodyWeightKg = kg
        let updated = photos[index]
        setPending(pending().filter { $0.id != photo.id } + [updated])
        await sync()
    }

    func delete(_ photo: ProgressPhoto) async {
        photos.removeAll { $0.id == photo.id }
        setPending(pending().filter { $0.id != photo.id })
        try? FileManager.default.removeItem(at: fileURL(photo.id))
        thumbnails.removeObject(forKey: photo.id.uuidString as NSString)
        do {
            try await repository.delete(photo)
        } catch {
            errorMessage = "Deleted here; the server copy goes next time you're online."
        }
    }

    // MARK: Sync

    func refresh() async {
        await sync()
        do {
            let remote = try await repository.list()
            let queued = pending()
            let queuedIDs = Set(queued.map(\.id))
            photos = (remote.filter { !queuedIDs.contains($0.id) } + queued).sorted { $0.takenAt > $1.takenAt }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load photos from the server. Showing what's on this phone."
        }
    }

    /// Single-flight upload of queued photos; each leaves the queue only once uploaded.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            pendingCount = pending().count
        }
        var attempted = Set<UUID>()
        while var photo = pending().first(where: { !attempted.contains($0.id) }) {
            attempted.insert(photo.id)
            // Photos taken before sign-in finished get moved into the user's folder.
            if photo.storagePath.hasPrefix("local/"), let folder = repository.userFolder() {
                photo.storagePath = "\(folder)/\(photo.id.uuidString.lowercased()).jpg"
            }
            guard let data = try? Data(contentsOf: fileURL(photo.id)) else {
                setPending(pending().filter { $0.id != photo.id })
                continue
            }
            do {
                try await repository.upload(photo, jpeg: data)
                setPending(pending().filter { $0.id != photo.id })
                if let index = photos.firstIndex(where: { $0.id == photo.id }) { photos[index] = photo }
                uploadError = nil
            } catch {
                uploadError = Self.describe(error)
                continue
            }
        }
    }

    /// Readable reason for a failed upload (storage and database errors carry a message).
    static func describe(_ error: Error) -> String {
        let text = String(describing: error)
        if let range = text.range(of: "message: \""), let end = text[range.upperBound...].firstIndex(of: "\"") {
            return String(text[range.upperBound..<end])
        }
        return error.localizedDescription
    }

    // MARK: Images

    /// Full-resolution image: local file, else downloaded once and cached.
    func image(for photo: ProgressPhoto) async -> UIImage? {
        if let data = try? Data(contentsOf: fileURL(photo.id)) { return UIImage(data: data) }
        guard let data = try? await repository.download(photo) else { return nil }
        try? data.write(to: fileURL(photo.id), options: .atomic)
        return UIImage(data: data)
    }

    /// Downsampled image for grids (fast, memory-light).
    func thumbnail(for photo: ProgressPhoto, maxPixel: CGFloat = 600) async -> UIImage? {
        let key = "\(photo.id.uuidString)-\(Int(maxPixel))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        if !FileManager.default.fileExists(atPath: fileURL(photo.id).path) {
            _ = await image(for: photo)
        }
        let url = fileURL(photo.id)
        let thumb = await Task.detached(priority: .userInitiated) { Self.downsample(url, maxPixel: maxPixel) }.value
        if let thumb { thumbnails.setObject(thumb, forKey: key) }
        return thumb
    }

    // MARK: Files

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }
    private var pendingURL: URL { directory.appendingPathComponent("pending.json") }

    private func pending() -> [ProgressPhoto] {
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ProgressPhoto].self, from: data)) ?? []
    }

    private func setPending(_ list: [ProgressPhoto]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if list.isEmpty {
            try? FileManager.default.removeItem(at: pendingURL)
        } else if let data = try? encoder.encode(list) {
            try? data.write(to: pendingURL, options: .atomic)
        }
        pendingCount = list.count
    }

    /// Long edge 2000 px, JPEG 0.82: sharp enough to compare definition, ~400 KB.
    nonisolated static func jpeg(_ image: UIImage, maxPixel: CGFloat = 2000) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let scale = longest > maxPixel ? maxPixel / longest : 1
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }

    nonisolated static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Original capture date from EXIF, for imports from the camera roll.
    nonisolated static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }
}
