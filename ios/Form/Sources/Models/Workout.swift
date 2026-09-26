import Foundation

// MARK: - Local draft (the active workout, persisted to disk after every change)

enum SetKind: String, Codable, Sendable, CaseIterable {
    case warmup, normal, drop, failure
}

struct DraftSet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: SetKind = .normal
    var weight: Double
    var reps: Int
    var completedAt: Date?
    /// Seconds held, for timed exercises.
    var durationSeconds: Int? = nil

    var isDone: Bool { completedAt != nil }
}

struct DraftExercise: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var exerciseRef: String
    var sets: [DraftSet]
    var restSeconds: Int = 120
    var notes: String?
}

struct WorkoutDraft: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var exercises: [DraftExercise] = []
    var notes: String?

    var completedSets: [DraftSet] {
        exercises.flatMap(\.sets).filter { $0.isDone && $0.kind != .warmup }
    }

    var volume: Double {
        completedSets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }
}

// MARK: - Supabase rows (form schema)

struct WorkoutRow: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String?
    var whoopWorkoutId: String?
    var strain: Double?
    var avgHr: Int?
    var maxHr: Int?
    var kcal: Int?
    var workoutExercises: [WorkoutExerciseRow]?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, strain, kcal
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case whoopWorkoutId = "whoop_workout_id"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case workoutExercises = "workout_exercises"
    }
}

struct WorkoutExerciseRow: Codable, Identifiable, Sendable {
    let id: UUID
    var workoutId: UUID
    var exerciseRef: String
    var position: Int
    var notes: String?
    var sets: [SetRow]?

    enum CodingKeys: String, CodingKey {
        case id, position, notes, sets
        case workoutId = "workout_id"
        case exerciseRef = "exercise_ref"
    }
}

struct SetRow: Codable, Identifiable, Sendable {
    let id: UUID
    var workoutExerciseId: UUID
    var position: Int
    var kind: SetKind
    var weightKg: Double?
    var reps: Int?
    var completedAt: Date?
    var durationSeconds: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, position, kind, reps
        case workoutExerciseId = "workout_exercise_id"
        case weightKg = "weight_kg"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Conversions

extension WorkoutDraft {
    /// Splits the draft into the three row types. Client-side UUIDs make saving idempotent (upsert).
    func rows() -> (workout: WorkoutRow, exercises: [WorkoutExerciseRow], sets: [SetRow]) {
        let workout = WorkoutRow(id: id, name: name, startedAt: startedAt, endedAt: endedAt, notes: notes)
        var exerciseRows: [WorkoutExerciseRow] = []
        var setRows: [SetRow] = []
        for (position, exercise) in exercises.enumerated() {
            let done = exercise.sets.filter(\.isDone)
            guard !done.isEmpty else { continue }
            exerciseRows.append(WorkoutExerciseRow(
                id: exercise.id, workoutId: id, exerciseRef: exercise.exerciseRef,
                position: position, notes: exercise.notes
            ))
            for (setPosition, set) in done.enumerated() {
                setRows.append(SetRow(
                    id: set.id, workoutExerciseId: exercise.id, position: setPosition,
                    kind: set.kind, weightKg: set.weight, reps: set.reps, completedAt: set.completedAt,
                    durationSeconds: set.durationSeconds
                ))
            }
        }
        return (workout, exerciseRows, setRows)
    }
}

extension WorkoutRow {
    var sortedExercises: [WorkoutExerciseRow] {
        (workoutExercises ?? []).sorted { $0.position < $1.position }
    }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    var volume: Double {
        var total = 0.0
        for exercise in sortedExercises {
            for set in exercise.sets ?? [] where set.kind != .warmup {
                let weight: Double = set.weightKg ?? 0
                let reps = Double(set.reps ?? 0)
                total += weight * reps
            }
        }
        return total
    }
}

extension WorkoutExerciseRow {
    var sortedSets: [SetRow] { (sets ?? []).sorted { $0.position < $1.position } }

    /// Best working set in the exercise's own terms: longest hold, most reps, or heaviest.
    func bestSet(metric: ExerciseMetric) -> SetRow? {
        let working = sortedSets.filter { $0.kind != .warmup }
        switch metric {
        case .duration: return working.max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }
        case .bodyweightReps: return working.max { ($0.reps ?? 0, $0.weightKg ?? 0) < ($1.reps ?? 0, $1.weightKg ?? 0) }
        case .weightReps: return topSet
        }
    }

    /// Heaviest working set, for summaries like "82.5 × 8".
    var topSet: SetRow? {
        sortedSets.filter { $0.kind != .warmup }.max {
            ($0.weightKg ?? 0, $0.reps ?? 0) < ($1.weightKg ?? 0, $1.reps ?? 0)
        }
    }
}

// MARK: - Formatting

enum SetFormat {
    /// "1:05", "0:45"
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// One set, in the exercise's own terms: "82.5 × 8", "12 reps", "+10 kg × 6", "1:05".
    static func describe(weight: Double, reps: Int, duration: Int?, metric: ExerciseMetric) -> String {
        switch metric {
        case .weightReps:
            return "\(weight.kg) × \(reps)"
        case .bodyweightReps:
            return weight > 0 ? "+\(weight.kg) kg × \(reps)" : "\(reps) reps"
        case .duration:
            let hold = clock(duration ?? 0)
            return weight > 0 ? "\(hold) +\(weight.kg) kg" : hold
        }
    }

    static func describe(_ set: SetRow, metric: ExerciseMetric) -> String {
        describe(weight: set.weightKg ?? 0, reps: set.reps ?? 0, duration: set.durationSeconds, metric: metric)
    }

    static func describe(_ set: DraftSet, metric: ExerciseMetric) -> String {
        describe(weight: set.weight, reps: set.reps, duration: set.durationSeconds, metric: metric)
    }
}
