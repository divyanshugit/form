import Foundation
import Supabase

protocol CustomExerciseRepository: Sendable {
    func list() async throws -> [CustomExerciseRow]
    func upsert(_ row: CustomExerciseRow) async throws
    func delete(id: UUID) async throws
}

struct SupabaseCustomExerciseRepository: CustomExerciseRepository {
    func list() async throws -> [CustomExerciseRow] {
        try await supabase.from("custom_exercises")
            .select("id, name, equipment, primary_muscle, secondary_muscles, metric, description")
            .execute().value
    }

    func upsert(_ row: CustomExerciseRow) async throws {
        try await supabase.from("custom_exercises").upsert(row).execute()
    }

    func delete(id: UUID) async throws {
        try await supabase.from("custom_exercises").delete().eq("id", value: id).execute()
    }
}

final class MockCustomExerciseRepository: CustomExerciseRepository, @unchecked Sendable {
    var rows: [CustomExerciseRow] = []
    var failWrites = false

    func list() async throws -> [CustomExerciseRow] { rows }

    func upsert(_ row: CustomExerciseRow) async throws {
        if failWrites { throw URLError(.notConnectedToInternet) }
        rows.removeAll { $0.id == row.id }
        rows.append(row)
    }

    func delete(id: UUID) async throws {
        rows.removeAll { $0.id == id }
    }
}
