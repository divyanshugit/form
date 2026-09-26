import Foundation
import Supabase

protocol PhotoRepository: Sendable {
    func list() async throws -> [ProgressPhoto]
    func upload(_ photo: ProgressPhoto, jpeg: Data) async throws
    func download(_ photo: ProgressPhoto) async throws -> Data
    func delete(_ photo: ProgressPhoto) async throws
    /// Folder for the signed-in user's files ({user_id}); storage RLS only allows this prefix.
    func userFolder() -> String?
}

struct SupabasePhotoRepository: PhotoRepository {
    private var bucket: StorageFileApi { supabase.storage.from("form-photos") }

    func list() async throws -> [ProgressPhoto] {
        try await supabase.from("photos").select().order("taken_at", ascending: false).execute().value
    }

    func upload(_ photo: ProgressPhoto, jpeg: Data) async throws {
        // File first, then the row: a row never points at a missing file.
        try await bucket.upload(photo.storagePath, data: jpeg,
                                options: FileOptions(contentType: "image/jpeg", upsert: true))
        try await supabase.from("photos").upsert(photo).execute()
    }

    func download(_ photo: ProgressPhoto) async throws -> Data {
        try await bucket.download(path: photo.storagePath)
    }

    func delete(_ photo: ProgressPhoto) async throws {
        try await supabase.from("photos").delete().eq("id", value: photo.id).execute()
        _ = try? await bucket.remove(paths: [photo.storagePath])
    }

    func userFolder() -> String? {
        supabase.auth.currentUser?.id.uuidString.lowercased()
    }
}

/// In-memory repository for previews, demo mode and tests.
final class MockPhotoRepository: PhotoRepository, @unchecked Sendable {
    var photos: [ProgressPhoto] = []
    var files: [String: Data] = [:]
    var failUploads = false

    func list() async throws -> [ProgressPhoto] { photos.sorted { $0.takenAt > $1.takenAt } }

    func upload(_ photo: ProgressPhoto, jpeg: Data) async throws {
        if failUploads { throw URLError(.notConnectedToInternet) }
        files[photo.storagePath] = jpeg
        photos.removeAll { $0.id == photo.id }
        photos.append(photo)
    }

    func download(_ photo: ProgressPhoto) async throws -> Data {
        guard let data = files[photo.storagePath] else { throw URLError(.fileDoesNotExist) }
        return data
    }

    func delete(_ photo: ProgressPhoto) async throws {
        photos.removeAll { $0.id == photo.id }
        files[photo.storagePath] = nil
    }

    func userFolder() -> String? { "demo" }
}
