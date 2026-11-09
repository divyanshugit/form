import Foundation

/// One measured number at a point in time (`form.metrics`): body weight, waist, a test result,
/// a HYROX station split, a protein check-in, a milestone ticked by hand.
struct MetricRow: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var recordedAt: Date
    var kind: String
    var value: Double
    var workoutId: UUID? = nil
    var note: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, value, note
        case recordedAt = "recorded_at"
        case workoutId = "workout_id"
    }
}

/// Metric kinds. Plain strings so new kinds never need a migration.
enum MetricKind {
    static let weight = "weight_kg"
    static let waist = "waist_cm"
    static let proteinOK = "protein_ok"
    static let soreness = "soreness"          // 1 (fresh) … 5 (wrecked)
    static let deload = "deload"              // value 1 on the day a deload week starts
    static let runSeconds = "run_s"           // with workout_id; distance comes from WHOOP or run_m
    static let runMeters = "run_m"
    static let runRPE = "run_rpe"

    static func test(_ name: String) -> String { "test:\(name)" }
    static func hyrox(_ station: String) -> String { "hyrox:\(station)" }
    static func milestone(_ id: String) -> String { "milestone:\(id)" }
    static let celebratedPrefix = "celebrated:"
}

/// Baseline and repeat tests (goals.md, Nov 27–30).
enum TestKind: String, CaseIterable, Identifiable, Sendable {
    case runSeconds = "run_s", runMeters = "run_m"
    case hyroxTotal = "hyrox_total_s"
    case pullupsMax = "pullups_max", deadlift5RM = "deadlift_5rm_kg", deadHang = "dead_hang_s", pushupsMax = "pushups_max"
    case lsitHold = "lsit_s"

    var id: String { rawValue }
    var metric: String { MetricKind.test(rawValue) }

    var title: String {
        switch self {
        case .runSeconds: "Run time"
        case .runMeters: "Run distance"
        case .hyroxTotal: "HYROX sim total"
        case .pullupsMax: "Max strict pull-ups"
        case .deadlift5RM: "Deadlift 5-rep weight"
        case .deadHang: "Dead hang"
        case .pushupsMax: "Push-up max"
        case .lsitHold: "L-sit hold"
        }
    }

    enum Unit { case seconds, meters, reps, kg }

    var unit: Unit {
        switch self {
        case .runSeconds, .hyroxTotal, .deadHang, .lsitHold: .seconds
        case .runMeters: .meters
        case .pullupsMax, .pushupsMax: .reps
        case .deadlift5RM: .kg
        }
    }

    /// Lower is better for times over a fixed course.
    var lowerIsBetter: Bool { self == .runSeconds || self == .hyroxTotal }

    func format(_ value: Double) -> String {
        switch unit {
        case .seconds: value >= 3600
            ? String(format: "%d:%02d:%02d", Int(value) / 3600, Int(value) % 3600 / 60, Int(value) % 60)
            : SetFormat.clock(Int(value))
        case .meters: value >= 1000 ? String(format: "%.2f km", value / 1000) : "\(Int(value)) m"
        case .reps: "\(Int(value))"
        case .kg: "\(value.kg) kg"
        }
    }
}

/// HYROX stations in race order.
enum HyroxStation: String, CaseIterable, Identifiable, Sendable {
    case ski, sledPush = "sled_push", sledPull = "sled_pull", burpees, row, farmers, lunges, wallBalls = "wall_balls"

    var id: String { rawValue }
    var metric: String { MetricKind.hyrox(rawValue) }

    /// Fits above a few minutes of a timeline.
    var short: String {
        switch self {
        case .ski: "SKI"
        case .sledPush: "PUSH"
        case .sledPull: "PULL"
        case .burpees: "BBJ"
        case .row: "ROW"
        case .farmers: "CARRY"
        case .lunges: "LUNGE"
        case .wallBalls: "WB"
        }
    }

    var title: String {
        switch self {
        case .ski: "SkiErg"
        case .sledPush: "Sled push"
        case .sledPull: "Sled pull"
        case .burpees: "Burpee broad jumps"
        case .row: "Row"
        case .farmers: "Farmers carry"
        case .lunges: "Sandbag lunges"
        case .wallBalls: "Wall balls"
        }
    }
}

enum MetricMath {
    /// Points of one kind, oldest first.
    static func series(_ metrics: [MetricRow], kind: String) -> [MetricRow] {
        metrics.filter { $0.kind == kind }.sorted { $0.recordedAt < $1.recordedAt }
    }

    static func latest(_ metrics: [MetricRow], kind: String) -> MetricRow? {
        metrics.filter { $0.kind == kind }.max { $0.recordedAt < $1.recordedAt }
    }

    /// Trailing 7-day mean at each point's day (one value per day: the day's mean).
    static func movingAverage(_ points: [(date: Date, value: Double)], days: Int = 7,
                              calendar: Calendar = .current) -> [(date: Date, value: Double)] {
        let byDay = Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.map(\.value).reduce(0, +) / Double($0.count) }
        let daysSorted = byDay.keys.sorted()
        return daysSorted.map { day in
            let from = calendar.date(byAdding: .day, value: -(days - 1), to: day)!
            let window = daysSorted.filter { $0 >= from && $0 <= day }.compactMap { byDay[$0] }
            return (day, window.reduce(0, +) / Double(window.count))
        }
    }

    /// Mean of the points in [end − days, end].
    static func average(_ points: [(date: Date, value: Double)], endingAt end: Date, days: Int = 7) -> Double? {
        let from = end.addingTimeInterval(-Double(days) * 86_400)
        let window = points.filter { $0.date > from && $0.date <= end }.map(\.value)
        return window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
    }
}
