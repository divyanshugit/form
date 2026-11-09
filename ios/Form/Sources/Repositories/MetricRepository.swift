import Foundation
import Supabase

protocol MetricRepository: Sendable {
    func list() async throws -> [MetricRow]
    func upsert(_ rows: [MetricRow]) async throws
    func delete(id: UUID) async throws
}

struct SupabaseMetricRepository: MetricRepository {
    func list() async throws -> [MetricRow] {
        try await supabase.from("metrics")
            .select("id, recorded_at, kind, value, workout_id, note")
            .order("recorded_at", ascending: false)
            .limit(10_000)
            .execute().value
    }

    func upsert(_ rows: [MetricRow]) async throws {
        guard !rows.isEmpty else { return }
        try await supabase.from("metrics").upsert(rows).execute()
    }

    func delete(id: UUID) async throws {
        try await supabase.from("metrics").delete().eq("id", value: id).execute()
    }
}

final class MockMetricRepository: MetricRepository, @unchecked Sendable {
    var rows: [MetricRow] = []
    var failWrites = false

    init(rows: [MetricRow] = []) { self.rows = rows }

    func list() async throws -> [MetricRow] { rows }

    func upsert(_ new: [MetricRow]) async throws {
        if failWrites { throw URLError(.notConnectedToInternet) }
        let ids = Set(new.map(\.id))
        rows = rows.filter { !ids.contains($0.id) } + new
    }

    func delete(id: UUID) async throws {
        if failWrites { throw URLError(.notConnectedToInternet) }
        rows.removeAll { $0.id == id }
    }
}
