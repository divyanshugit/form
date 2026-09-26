import Foundation

/// Crash-safe local storage for the active workout and for finished workouts waiting to upload.
/// Gyms have bad signal: nothing depends on the network until sync.
struct DraftStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Form", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directory = base
    }

    private var activeURL: URL { directory.appendingPathComponent("active-workout.json") }
    private var pendingURL: URL { directory.appendingPathComponent("pending-uploads.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Active workout

    func saveActive(_ draft: WorkoutDraft) {
        guard let data = try? Self.encoder.encode(draft) else { return }
        try? data.write(to: activeURL, options: .atomic)
    }

    func loadActive() -> WorkoutDraft? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? Self.decoder.decode(WorkoutDraft.self, from: data)
    }

    func clearActive() {
        try? FileManager.default.removeItem(at: activeURL)
    }

    // MARK: Pending uploads

    func pending() -> [WorkoutDraft] {
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        return (try? Self.decoder.decode([WorkoutDraft].self, from: data)) ?? []
    }

    func setPending(_ drafts: [WorkoutDraft]) {
        if drafts.isEmpty {
            try? FileManager.default.removeItem(at: pendingURL)
        } else if let data = try? Self.encoder.encode(drafts) {
            try? data.write(to: pendingURL, options: .atomic)
        }
    }
}
