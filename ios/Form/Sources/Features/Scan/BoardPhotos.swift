import UIKit

/// Whiteboard photos kept with their session on this phone (Library/Application Support/Form/boards).
enum BoardPhotos {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Form/boards", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for sessionID: UUID) -> URL {
        directory.appendingPathComponent("\(sessionID.uuidString.lowercased()).jpg")
    }

    static func save(_ image: UIImage, for sessionID: UUID) {
        guard let data = PhotoStore.jpeg(image, maxPixel: 1600) else { return }
        try? data.write(to: url(for: sessionID), options: .atomic)
    }

    static func exists(for sessionID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: sessionID).path)
    }

    static func image(for sessionID: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(for: sessionID).path)
    }
}
