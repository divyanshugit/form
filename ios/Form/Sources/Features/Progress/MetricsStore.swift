import Foundation

/// Body measures, test results, splits, check-ins and milestone ticks. Written to the phone first,
/// then pushed to `form.metrics`; deletes made offline are replayed too.
@MainActor
@Observable
final class MetricsStore {
    private(set) var rows: [MetricRow] = []
    var errorMessage: String?

    private let repository: MetricRepository
    private let fileURL: URL
    private let pendingURL: URL
    private let deletedURL: URL
    @ObservationIgnored private var isSyncing = false

    init(repository: MetricRepository = SupabaseMetricRepository(), directory: URL? = nil) {
        self.repository = repository
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Form", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("metrics.json")
        pendingURL = base.appendingPathComponent("metrics-pending.json")
        deletedURL = base.appendingPathComponent("metrics-deleted.json")
        rows = Self.read([MetricRow].self, from: fileURL) ?? []
    }

    // MARK: Reading

    func series(_ kind: String) -> [MetricRow] { MetricMath.series(rows, kind: kind) }
    func latest(_ kind: String) -> MetricRow? { MetricMath.latest(rows, kind: kind) }

    /// The value recorded for `kind` on the same calendar day as `date`, if any.
    func entry(_ kind: String, on date: Date, calendar: Calendar = .current) -> MetricRow? {
        rows.first { $0.kind == kind && calendar.isDate($0.recordedAt, inSameDayAs: date) }
    }

    /// Metrics recorded against a session (HYROX splits, run time).
    func metrics(for workoutID: UUID) -> [MetricRow] { rows.filter { $0.workoutId == workoutID } }

    // MARK: Writing

    func record(_ kind: String, _ value: Double, at date: Date = .now, workoutID: UUID? = nil, note: String? = nil) async {
        await save([MetricRow(recordedAt: date, kind: kind, value: value, workoutId: workoutID, note: note)])
    }

    /// One value per kind per day (weight, protein check): replaces that day's entry.
    func setDaily(_ kind: String, _ value: Double, on date: Date = .now) async {
        var row = entry(kind, on: date) ?? MetricRow(recordedAt: date, kind: kind, value: value)
        row.value = value
        await save([row])
    }

    /// One value per kind per session (a HYROX split, run time): replaces that session's entry.
    func setForWorkout(_ kind: String, _ value: Double?, workoutID: UUID, at date: Date) async {
        let existing = rows.first { $0.kind == kind && $0.workoutId == workoutID }
        guard let value else {
            if let existing { await delete(existing.id) }
            return
        }
        var row = existing ?? MetricRow(recordedAt: date, kind: kind, value: value, workoutId: workoutID)
        row.value = value
        await save([row])
    }

    func save(_ new: [MetricRow]) async {
        let ids = Set(new.map(\.id))
        rows = rows.filter { !ids.contains($0.id) } + new
        persist()
        Self.write(Array(pendingIDs().union(ids)), to: pendingURL)
        await sync()
    }

    func delete(_ id: UUID) async {
        rows.removeAll { $0.id == id }
        persist()
        Self.write(Array(pendingIDs().subtracting([id])), to: pendingURL)
        Self.write(Array(deletedIDs().union([id])), to: deletedURL)
        await sync()
    }

    // MARK: Sync

    func refresh() async {
        await sync()
        do {
            let remote = try await repository.list()
            let pending = pendingIDs()
            let deleted = deletedIDs()
            rows = remote.filter { !pending.contains($0.id) && !deleted.contains($0.id) }
                + rows.filter { pending.contains($0.id) }
            persist()
        } catch {
            // Offline, or not migrated yet: keep the phone's copy.
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let pending = pendingIDs()
        let batch = rows.filter { pending.contains($0.id) }
        do {
            try await repository.upsert(batch)
            Self.write(Array(pendingIDs().subtracting(batch.map(\.id))), to: pendingURL)
            for id in deletedIDs() {
                try await repository.delete(id: id)
                Self.write(Array(deletedIDs().subtracting([id])), to: deletedURL)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Saved on this phone. It'll sync when the server is reachable."
        }
    }

    var pendingCount: Int { pendingIDs().count + deletedIDs().count }

    // MARK: Storage

    private func persist() { Self.write(rows, to: fileURL) }
    private func pendingIDs() -> Set<UUID> { Set(Self.read([UUID].self, from: pendingURL) ?? []) }
    private func deletedIDs() -> Set<UUID> { Set(Self.read([UUID].self, from: deletedURL) ?? []) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
