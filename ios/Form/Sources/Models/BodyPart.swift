import Foundation

/// The six groups the Body tab navigates by. Each owns a set of free-exercise-db muscle names.
enum BodyPart: String, CaseIterable, Identifiable, Hashable {
    case chest, back, shoulders, arms, legs, core

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// free-exercise-db `primaryMuscles` values, in display order.
    var muscles: [String] {
        switch self {
        case .chest: ["chest"]
        case .back: ["lats", "middle back", "lower back", "traps"]
        case .shoulders: ["shoulders", "neck"]
        case .arms: ["biceps", "triceps", "forearms"]
        case .legs: ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
        case .core: ["abdominals"]
        }
    }

    init?(muscle: String) {
        let key = muscle.lowercased()
        guard let part = Self.allCases.first(where: { $0.muscles.contains(key) }) else { return nil }
        self = part
    }

    /// Region slugs used by the body-map artwork.
    init?(mapSlug: String) {
        switch mapSlug {
        case "chest": self = .chest
        case "trapezius", "upper-back", "lower-back": self = .back
        case "deltoids": self = .shoulders
        case "biceps", "triceps", "forearm": self = .arms
        case "quadriceps", "hamstring", "gluteal", "calves", "adductors", "tibialis": self = .legs
        case "abs", "obliques": self = .core
        default: return nil
        }
    }

    /// The side of the body map where this group is most visible.
    var prefersBackView: Bool { self == .back }
}

extension Exercise {
    var bodyPart: BodyPart? { primaryMuscles.first.flatMap(BodyPart.init(muscle:)) }
}

/// How recently a body part was trained; drives the map tint.
enum Freshness: Equatable {
    case fresh   // within 2 days
    case recent  // 3–5 days
    case stale   // 6+ days or never

    init(daysSince: Int?) {
        switch daysSince {
        case .some(let d) where d <= 2: self = .fresh
        case .some(let d) where d <= 5: self = .recent
        default: self = .stale
        }
    }
}

struct BodyPartStats: Equatable {
    var lastTrained: Date?
    /// Completed working sets (warmups excluded) in the last 7 days.
    var recentSets = 0
    var daysSince: Int?

    var freshness: Freshness { Freshness(daysSince: daysSince) }
}

enum BodyStats {
    static let window = 7

    /// Per-body-part recency and set counts. Only an exercise's first primary muscle counts.
    static func compute(history: [WorkoutRow], library: ExerciseLibrary,
                        now: Date = .now, calendar: Calendar = .current) -> [BodyPart: BodyPartStats] {
        var stats = Dictionary(uniqueKeysWithValues: BodyPart.allCases.map { ($0, BodyPartStats()) })
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(window - 1), to: today) ?? today

        for workout in history {
            for exercise in workout.workoutExercises ?? [] {
                guard let part = library.exercise(exercise.exerciseRef)?.bodyPart else { continue }
                let working = (exercise.sets ?? []).filter { $0.kind != .warmup }
                guard !working.isEmpty else { continue }
                if stats[part]?.lastTrained.map({ workout.startedAt > $0 }) ?? true {
                    stats[part]?.lastTrained = workout.startedAt
                }
                if workout.startedAt >= windowStart {
                    stats[part]?.recentSets += working.count
                }
            }
        }
        for part in BodyPart.allCases {
            guard let last = stats[part]?.lastTrained else { continue }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: today).day ?? 0
            stats[part]?.daysSince = max(0, days)
        }
        return stats
    }

    /// Most recent session date per exercise ref.
    static func lastDone(history: [WorkoutRow]) -> [String: Date] {
        var result: [String: Date] = [:]
        for workout in history {
            for exercise in workout.workoutExercises ?? [] where !(exercise.sets ?? []).isEmpty {
                if result[exercise.exerciseRef].map({ workout.startedAt > $0 }) ?? true {
                    result[exercise.exerciseRef] = workout.startedAt
                }
            }
        }
        return result
    }

    /// Sessions and working sets in the window, across all body parts.
    static func summary(history: [WorkoutRow], now: Date = .now, calendar: Calendar = .current) -> (sessions: Int, sets: Int) {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(window - 1), to: today) ?? today
        let recent = history.filter { $0.startedAt >= windowStart }
        let sets = recent.reduce(0) { total, workout in
            total + (workout.workoutExercises ?? []).reduce(0) { $0 + ($1.sets ?? []).filter { $0.kind != .warmup }.count }
        }
        return (recent.count, sets)
    }

    static func ago(_ days: Int?) -> String {
        switch days {
        case nil: "never"
        case 0: "today"
        case 1: "yesterday"
        case let d?: "\(d)d ago"
        }
    }
}
