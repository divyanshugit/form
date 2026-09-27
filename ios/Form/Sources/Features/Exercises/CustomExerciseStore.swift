import Foundation

/// Your own exercises. Saved on the phone first, pushed to Supabase, and registered with the
/// exercise library so pickers, workouts, history and records all see them.
@MainActor
@Observable
final class CustomExerciseStore {
    private(set) var rows: [CustomExerciseRow] = []
    var errorMessage: String?

    private let repository: CustomExerciseRepository
    private let library: ExerciseLibrary
    private let fileURL: URL
    private let pendingURL: URL
    @ObservationIgnored private var isSyncing = false

    init(repository: CustomExerciseRepository = SupabaseCustomExerciseRepository(),
         library: ExerciseLibrary = .shared,
         directory: URL? = nil) {
        self.repository = repository
        self.library = library
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Form", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("custom-exercises.json")
        pendingURL = base.appendingPathComponent("custom-exercises-pending.json")
        rows = Self.read([CustomExerciseRow].self, from: fileURL) ?? []
        publish()
    }

    var exercises: [Exercise] { library.custom }

    // MARK: Editing

    @discardableResult
    func save(_ row: CustomExerciseRow) async -> Exercise {
        rows.removeAll { $0.id == row.id }
        rows.append(row)
        persist()
        markPending(row.id)
        await sync()
        return row.exercise
    }

    func delete(_ id: UUID) async {
        rows.removeAll { $0.id == id }
        persist()
        unmarkPending(id)
        do { try await repository.delete(id: id) } catch {
            errorMessage = "Removed here; the server copy goes next time you're online."
        }
    }

    func row(for exercise: Exercise) -> CustomExerciseRow? {
        guard exercise.isCustom else { return nil }
        let raw = exercise.id.dropFirst(Exercise.customPrefix.count)
        return rows.first { $0.id.uuidString.lowercased() == raw }
    }

    // MARK: Sync

    func refresh() async {
        await sync()
        do {
            let remote = try await repository.list()
            let pending = pendingIDs()
            rows = remote.filter { !pending.contains($0.id) } + rows.filter { pending.contains($0.id) }
            persist()
            errorMessage = nil
        } catch {
            // Offline or table not migrated yet: keep what's on the phone.
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        for id in pendingIDs() {
            guard let row = rows.first(where: { $0.id == id }) else {
                unmarkPending(id)
                continue
            }
            do {
                try await repository.upsert(row)
                unmarkPending(id)
                errorMessage = nil
            } catch {
                errorMessage = "Saved on this phone. It'll sync when the server is reachable."
            }
        }
    }

    // MARK: Storage

    private func publish() {
        library.setCustom(rows.map(\.exercise))
    }

    private func persist() {
        Self.write(rows, to: fileURL)
        publish()
    }

    private func pendingIDs() -> Set<UUID> { Set(Self.read([UUID].self, from: pendingURL) ?? []) }
    private func markPending(_ id: UUID) { Self.write(Array(pendingIDs().union([id])), to: pendingURL) }
    private func unmarkPending(_ id: UUID) { Self.write(Array(pendingIDs().subtracting([id])), to: pendingURL) }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
