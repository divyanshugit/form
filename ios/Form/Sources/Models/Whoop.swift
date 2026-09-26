import Foundation

// WHOOP API v2 payloads (snake_case JSON, decoded with .convertFromSnakeCase).

struct WhoopPage<T: Decodable & Sendable>: Decodable, Sendable {
    let records: [T]
    let nextToken: String?
}

enum WhoopScoreState: String, Decodable, Sendable {
    case scored = "SCORED", pendingScore = "PENDING_SCORE", unscorable = "UNSCORABLE"
}

struct WhoopRecovery: Decodable, Sendable {
    struct Score: Decodable, Sendable {
        let recoveryScore: Double
        let restingHeartRate: Double
        let hrvRmssdMilli: Double
        let userCalibrating: Bool?
    }
    let cycleId: Int
    let sleepId: String?
    let createdAt: Date
    let scoreState: WhoopScoreState
    let score: Score?
}

/// A WHOOP physiological day: day strain, calories and heart rate, with or without a logged workout.
struct WhoopCycle: Decodable, Identifiable, Sendable {
    struct Score: Decodable, Sendable {
        let strain: Double
        let kilojoule: Double
        let averageHeartRate: Int
        let maxHeartRate: Int
    }
    let id: Int
    let start: Date
    let end: Date?
    let scoreState: WhoopScoreState
    let score: Score?
}

/// One row of the 30-day view: a cycle joined with its recovery and main sleep.
struct WhoopDay: Identifiable, Sendable {
    let id: Int
    let date: Date
    let recovery: Double?
    let hrv: Double?
    let restingHeartRate: Double?
    let sleepHours: Double?
    let dayStrain: Double?
    let kcal: Int?
    let averageHeartRate: Int?

    static func build(cycles: [WhoopCycle], recoveries: [WhoopRecovery], sleeps: [WhoopSleep]) -> [WhoopDay] {
        let recoveryByCycle = Dictionary(recoveries.map { ($0.cycleId, $0) }, uniquingKeysWith: { a, _ in a })
        let sleepByID = Dictionary(sleeps.filter { !$0.nap }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return cycles.map { cycle in
            let recovery = recoveryByCycle[cycle.id]
            let sleep = recovery?.sleepId.flatMap { sleepByID[$0] }
                ?? sleeps.first { !$0.nap && $0.cycleId == cycle.id }
            return WhoopDay(
                id: cycle.id,
                date: cycle.start,
                recovery: recovery?.score?.recoveryScore,
                hrv: recovery?.score?.hrvRmssdMilli,
                restingHeartRate: recovery?.score?.restingHeartRate,
                sleepHours: sleep?.asleep.map { $0 / 3600 },
                dayStrain: cycle.score?.strain,
                kcal: cycle.score.map { Int(($0.kilojoule / 4.184).rounded()) },
                averageHeartRate: cycle.score?.averageHeartRate
            )
        }
        .sorted { $0.date < $1.date }
    }
}

struct WhoopSleep: Decodable, Sendable {
    struct Score: Decodable, Sendable {
        struct Stages: Decodable, Sendable {
            let totalInBedTimeMilli: Double
            let totalAwakeTimeMilli: Double
        }
        let stageSummary: Stages
        let sleepPerformancePercentage: Double?
    }
    let id: String
    let cycleId: Int?
    let start: Date
    let end: Date
    let nap: Bool
    let scoreState: WhoopScoreState
    let score: Score?

    var asleep: TimeInterval? {
        score.map { ($0.stageSummary.totalInBedTimeMilli - $0.stageSummary.totalAwakeTimeMilli) / 1000 }
    }
}

struct WhoopWorkout: Decodable, Identifiable, Sendable {
    struct Score: Decodable, Sendable {
        let strain: Double
        let averageHeartRate: Int
        let maxHeartRate: Int
        let kilojoule: Double
    }
    let id: String
    let start: Date
    let end: Date
    let sportName: String?
    let scoreState: WhoopScoreState
    let score: Score?

    var kcal: Int? { score.map { Int(($0.kilojoule / 4.184).rounded()) } }

    var displayName: String {
        guard let sportName, !sportName.isEmpty else { return "WHOOP activity" }
        return sportName.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

extension JSONDecoder {
    /// WHOOP timestamps look like 2026-09-26T06:58:12.774Z (fractional seconds optional).
    static let whoop: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }()
}

/// How recovery reads out loud on the Today card.
enum RecoveryTone {
    case charged, steady, low

    init(score: Double) {
        switch score {
        case 67...: self = .charged
        case 34..<67: self = .steady
        default: self = .low
        }
    }

    var headline: String {
        switch self {
        case .charged: "You're charged."
        case .steady: "Steady."
        case .low: "Low battery."
        }
    }

    var advice: String {
        switch self {
        case .charged: "Good day to go heavy."
        case .steady: "Train, but listen to your body."
        case .low: "Go light, or rest. Both count."
        }
    }
}

// MARK: - Matching WHOOP workouts to Form sessions

enum WhoopMatching {
    struct Plan: Sendable {
        /// Form session id → the WHOOP workout that overlaps it.
        var attach: [(workoutID: UUID, whoop: WhoopWorkout)] = []
        /// WHOOP-only workouts to import as their own sessions.
        var imports: [WhoopWorkout] = []
        /// Imported rows superseded by a Form session that now carries the same WHOOP data.
        var removeImported: [UUID] = []
    }

    /// Pure, testable. A WHOOP workout attaches to the Form session it overlaps most
    /// (at least half of the shorter of the two); otherwise it's imported, keyed by its own UUID.
    static func plan(formWorkouts: [WorkoutRow], whoop: [WhoopWorkout]) -> Plan {
        var plan = Plan()
        let scored = whoop.filter { $0.scoreState == .scored && $0.score != nil }
        let logged = formWorkouts.filter { !$0.isWhoopImport }
        let importedIDs = Set(formWorkouts.filter(\.isWhoopImport).map(\.id))
        var claimed = Set(logged.compactMap(\.whoopWorkoutId))

        for session in logged where session.whoopWorkoutId == nil {
            let end = session.endedAt ?? session.startedAt.addingTimeInterval(3600)
            let best = scored
                .filter { !claimed.contains($0.id) }
                .map { ($0, overlap($0.start, $0.end, session.startedAt, end)) }
                .filter { candidate, seconds in
                    let shorter = min(candidate.end.timeIntervalSince(candidate.start), end.timeIntervalSince(session.startedAt))
                    return shorter > 0 && seconds >= shorter * 0.5
                }
                .max { $0.1 < $1.1 }?.0
            if let best {
                plan.attach.append((session.id, best))
                claimed.insert(best.id)
                if let uuid = UUID(uuidString: best.id), importedIDs.contains(uuid) {
                    plan.removeImported.append(uuid)
                }
            }
        }

        for workout in scored where !claimed.contains(workout.id) {
            if let uuid = UUID(uuidString: workout.id), importedIDs.contains(uuid) { continue }
            plan.imports.append(workout)
        }
        return plan
    }

    static func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> TimeInterval {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}

extension WorkoutRow {
    /// Imported WHOOP-only sessions reuse the WHOOP workout UUID as their id and have no exercises.
    var isWhoopImport: Bool {
        whoopWorkoutId != nil && whoopWorkoutId?.lowercased() == id.uuidString.lowercased()
    }

    static func imported(from whoop: WhoopWorkout) -> WorkoutRow? {
        guard let id = UUID(uuidString: whoop.id), let score = whoop.score else { return nil }
        return WorkoutRow(
            id: id, name: whoop.displayName, startedAt: whoop.start, endedAt: whoop.end,
            whoopWorkoutId: whoop.id, strain: score.strain, avgHr: score.averageHeartRate,
            maxHr: score.maxHeartRate, kcal: whoop.kcal
        )
    }
}
