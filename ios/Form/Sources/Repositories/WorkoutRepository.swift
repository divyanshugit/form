import Foundation
import Supabase

protocol WorkoutRepository: Sendable {
    /// Recent workouts, newest first, with exercises and sets embedded.
    func recentWorkouts(limit: Int) async throws -> [WorkoutRow]
    /// Upserts a finished workout. Safe to retry: ids are generated on the device.
    func save(_ draft: WorkoutDraft) async throws
    func delete(workoutID: UUID) async throws
    /// Writes WHOOP strain / heart rate / calories onto a logged session.
    func attachWhoop(_ whoop: WhoopWorkout, to workoutID: UUID) async throws
    /// Upserts WHOOP-only sessions (their id is the WHOOP workout UUID, so this is idempotent).
    func upsertImported(_ rows: [WorkoutRow]) async throws
    /// Rewrites a session's name/notes and replaces its exercises and sets. WHOOP columns are untouched.
    func replace(_ draft: WorkoutDraft) async throws
}

struct WhoopFields: Encodable, Sendable {
    let whoop_workout_id: String
    let strain: Double
    let avg_hr: Int
    let max_hr: Int
    let kcal: Int?

    init?(_ whoop: WhoopWorkout) {
        guard let score = whoop.score else { return nil }
        whoop_workout_id = whoop.id
        strain = score.strain
        avg_hr = score.averageHeartRate
        max_hr = score.maxHeartRate
        kcal = whoop.kcal
    }
}

struct SupabaseWorkoutRepository: WorkoutRepository {
    func recentWorkouts(limit: Int = 60) async throws -> [WorkoutRow] {
        try await supabase
            .from("workouts")
            .select("*, workout_exercises(*, sets(*))")
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func save(_ draft: WorkoutDraft) async throws {
        let rows = draft.rows()
        try await supabase.from("workouts").upsert(rows.workout).execute()
        if !rows.exercises.isEmpty {
            try await supabase.from("workout_exercises").upsert(rows.exercises).execute()
        }
        if !rows.sets.isEmpty {
            try await supabase.from("sets").upsert(rows.sets).execute()
        }
    }

    func delete(workoutID: UUID) async throws {
        try await supabase.from("workouts").delete().eq("id", value: workoutID).execute()
    }

    func attachWhoop(_ whoop: WhoopWorkout, to workoutID: UUID) async throws {
        guard let fields = WhoopFields(whoop) else { return }
        try await supabase.from("workouts").update(fields).eq("id", value: workoutID).execute()
    }

    func upsertImported(_ rows: [WorkoutRow]) async throws {
        guard !rows.isEmpty else { return }
        for start in stride(from: 0, to: rows.count, by: 500) {
            try await supabase.from("workouts").upsert(Array(rows[start..<min(start + 500, rows.count)])).execute()
        }
    }

    func replace(_ draft: WorkoutDraft) async throws {
        // Write the new state first, then prune rows the edit removed. If the network drops midway,
        // the worst case is a leftover row, never a session with its sets wiped.
        try await save(draft)
        let rows = draft.rows()
        let exerciseIDs = rows.exercises.map(\.id.uuidString)
        let setIDs = rows.sets.map(\.id.uuidString)

        var staleExercises = supabase.from("workout_exercises").delete().eq("workout_id", value: draft.id)
        if !exerciseIDs.isEmpty {
            staleExercises = staleExercises.not("id", operator: .in, value: "(\(exerciseIDs.joined(separator: ",")))")
        }
        try await staleExercises.execute()

        if !exerciseIDs.isEmpty {
            var staleSets = supabase.from("sets").delete().in("workout_exercise_id", values: exerciseIDs)
            if !setIDs.isEmpty {
                staleSets = staleSets.not("id", operator: .in, value: "(\(setIDs.joined(separator: ",")))")
            }
            try await staleSets.execute()
        }
    }
}

/// In-memory repository for previews and tests.
final class MockWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    var workouts: [WorkoutRow]
    var failSaves = false

    init(workouts: [WorkoutRow] = []) {
        self.workouts = workouts
    }

    func recentWorkouts(limit: Int) async throws -> [WorkoutRow] {
        Array(workouts.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    func save(_ draft: WorkoutDraft) async throws {
        if failSaves { throw URLError(.notConnectedToInternet) }
        let rows = draft.rows()
        var workout = rows.workout
        workout.workoutExercises = rows.exercises.map { exercise in
            var e = exercise
            e.sets = rows.sets.filter { $0.workoutExerciseId == exercise.id }
            return e
        }
        workouts.removeAll { $0.id == workout.id }
        workouts.append(workout)
    }

    func delete(workoutID: UUID) async throws {
        workouts.removeAll { $0.id == workoutID }
    }

    func attachWhoop(_ whoop: WhoopWorkout, to workoutID: UUID) async throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }), let score = whoop.score else { return }
        workouts[index].whoopWorkoutId = whoop.id
        workouts[index].strain = score.strain
        workouts[index].avgHr = score.averageHeartRate
        workouts[index].maxHr = score.maxHeartRate
        workouts[index].kcal = whoop.kcal
    }

    func upsertImported(_ rows: [WorkoutRow]) async throws {
        for row in rows {
            workouts.removeAll { $0.id == row.id }
            workouts.append(row)
        }
    }

    func replace(_ draft: WorkoutDraft) async throws {
        let existing = workouts.first { $0.id == draft.id }
        try await save(draft)
        if let existing, let index = workouts.firstIndex(where: { $0.id == draft.id }) {
            workouts[index].whoopWorkoutId = existing.whoopWorkoutId
            workouts[index].strain = existing.strain
            workouts[index].avgHr = existing.avgHr
            workouts[index].maxHr = existing.maxHr
            workouts[index].kcal = existing.kcal
        }
    }
}
