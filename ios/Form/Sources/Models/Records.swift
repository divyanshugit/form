import Foundation

/// A personal record set during a workout.
struct PersonalRecord: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case estimatedOneRepMax, heaviest, mostReps, longestHold }

    var id: String { exerciseRef + kind.rawValue }
    let exerciseRef: String
    let kind: Kind
    let weight: Double
    let reps: Int
    var durationSeconds: Int? = nil
    let previousBest: Double?

    var estimatedOneRepMax: Double { PlateMath.estimatedOneRepMax(weight: weight, reps: reps) }
}

enum Records {
    /// Best efforts per exercise, measured every way that matters for its metric.
    struct Best: Sendable {
        var heaviest: Double = 0
        var oneRepMax: Double = 0
        var mostReps: Int = 0
        var longestHold: Int = 0
    }

    typealias MetricLookup = @Sendable (String) -> ExerciseMetric

    static let defaultMetric: MetricLookup = { ExerciseLibrary.shared.metric($0) }

    static func bests(in history: [WorkoutRow], excluding workoutID: UUID? = nil) -> [String: Best] {
        var result: [String: Best] = [:]
        for workout in history where workout.id != workoutID {
            for exercise in workout.sortedExercises {
                for set in exercise.sortedSets where set.kind != .warmup {
                    var best = result[exercise.exerciseRef, default: Best()]
                    let weight = set.weightKg ?? 0
                    let reps = set.reps ?? 0
                    if reps > 0 {
                        best.heaviest = max(best.heaviest, weight)
                        best.oneRepMax = max(best.oneRepMax, PlateMath.estimatedOneRepMax(weight: weight, reps: reps))
                        best.mostReps = max(best.mostReps, reps)
                    }
                    best.longestHold = max(best.longestHold, set.durationSeconds ?? 0)
                    result[exercise.exerciseRef] = best
                }
            }
        }
        return result
    }

    /// PRs in a draft compared with history. First-ever sessions of an exercise don't count as PRs.
    static func newRecords(in draft: WorkoutDraft, history: [WorkoutRow],
                           metric: MetricLookup = defaultMetric) -> [PersonalRecord] {
        let previous = bests(in: history, excluding: draft.id)
        var records: [PersonalRecord] = []
        for exercise in draft.exercises {
            guard let best = previous[exercise.exerciseRef] else { continue }
            let working = exercise.sets.filter { $0.isDone && $0.kind != .warmup }
            switch metric(exercise.exerciseRef) {
            case .duration:
                if let top = working.max(by: { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }),
                   let seconds = top.durationSeconds, seconds > best.longestHold {
                    records.append(PersonalRecord(exerciseRef: exercise.exerciseRef, kind: .longestHold,
                                                  weight: top.weight, reps: 0, durationSeconds: seconds,
                                                  previousBest: Double(best.longestHold)))
                }
            case .bodyweightReps:
                if let top = working.max(by: { $0.reps < $1.reps }), top.reps > best.mostReps {
                    records.append(PersonalRecord(exerciseRef: exercise.exerciseRef, kind: .mostReps,
                                                  weight: top.weight, reps: top.reps, previousBest: Double(best.mostReps)))
                }
            case .weightReps:
                let lifts = working.filter { $0.reps > 0 }
                if let top = lifts.max(by: {
                    PlateMath.estimatedOneRepMax(weight: $0.weight, reps: $0.reps)
                        < PlateMath.estimatedOneRepMax(weight: $1.weight, reps: $1.reps)
                }), PlateMath.estimatedOneRepMax(weight: top.weight, reps: top.reps) > best.oneRepMax + 0.01 {
                    records.append(PersonalRecord(exerciseRef: exercise.exerciseRef, kind: .estimatedOneRepMax,
                                                  weight: top.weight, reps: top.reps, previousBest: best.oneRepMax))
                } else if let heaviest = lifts.max(by: { $0.weight < $1.weight }), heaviest.weight > best.heaviest + 0.01 {
                    records.append(PersonalRecord(exerciseRef: exercise.exerciseRef, kind: .heaviest,
                                                  weight: heaviest.weight, reps: heaviest.reps, previousBest: best.heaviest))
                }
            }
        }
        return records
    }

    /// Most recent sets logged for an exercise, used for "last time" hints and pre-filling.
    /// `history` must be newest first (WorkoutStore keeps it that way).
    static func lastSets(for exerciseRef: String, in history: [WorkoutRow]) -> [SetRow]? {
        for workout in history {
            if let match = workout.sortedExercises.first(where: { $0.exerciseRef == exerciseRef }) {
                let sets = match.sortedSets.filter { $0.kind != .warmup }
                if !sets.isEmpty { return sets }
            }
        }
        return nil
    }

    /// One point per session: the best effort in that session, in the exercise's own unit
    /// (seconds for holds, reps for bodyweight, est. 1RM kg for lifts). Oldest first.
    static func trend(for exerciseRef: String, metric: ExerciseMetric, in history: [WorkoutRow]) -> [(date: Date, value: Double)] {
        history.compactMap { workout -> (Date, Double)? in
            let sets = workout.sortedExercises
                .filter { $0.exerciseRef == exerciseRef }
                .flatMap(\.sortedSets)
                .filter { $0.kind != .warmup }
            let values: [Double] = sets.map { set in
                switch metric {
                case .duration: Double(set.durationSeconds ?? 0)
                case .bodyweightReps: Double(set.reps ?? 0)
                case .weightReps: PlateMath.estimatedOneRepMax(weight: set.weightKg ?? 0, reps: set.reps ?? 0)
                }
            }
            guard let best = values.max(), best > 0 else { return nil }
            return (workout.startedAt, best)
        }
        .sorted { $0.0 < $1.0 }
        .map { (date: $0.0, value: $0.1) }
    }
}
