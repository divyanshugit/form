import Foundation

/// What I'm aiming for, from goals.md: phases with exit criteria, the Bali → India blocks,
/// the baseline test days and the weekly template. Static on purpose: it changes when the plan does.
enum Goals {
    static func day(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// Day 0 photo: the first day of training.
    static var dayZero: Date { day(2026, 9, 27) }
    static var start: Date { day(2026, 11, 9) }
    static let heightCm = 179.0
    static let baselineWeightKg = 70.5

    // MARK: Phases

    struct Phase: Identifiable, Sendable {
        let id: String
        let name: String
        let start: Date
        let end: Date
        let kcal: ClosedRange<Int>
        let protein: ClosedRange<Int>
        let focus: String
        let exit: [Criterion]
    }

    struct Criterion: Identifiable, Sendable {
        enum Check: Sendable {
            /// Met when this milestone is achieved.
            case milestone(String)
            /// Every main lift's best is up on its baseline.
            case liftsUp
            /// Latest waist ≤ baseline waist.
            case waistNotUp
            /// Ticked by hand.
            case manual
        }
        let id: String
        let title: String
        let check: Check
    }

    static var phases: [Phase] {
        [
            Phase(id: "foundation", name: "Foundation", start: day(2026, 11, 9), end: day(2027, 5, 31),
                  kcal: 2300...2300, protein: 130...150, focus: "Recomp. Learn the lifts, first pull-up, run 10 km.",
                  exit: [
                      Criterion(id: "p1_lifts", title: "Every main lift up from baseline", check: .liftsUp),
                      Criterion(id: "p1_pullups", title: "First strict pull-up → 5+ reps", check: .milestone("pullup_5")),
                      Criterion(id: "p1_10k", title: "Run 10 km continuously", check: .milestone("run_10k")),
                      Criterion(id: "p1_waist", title: "Waist same or smaller than baseline", check: .waistNotUp),
                  ]),
            Phase(id: "build", name: "Build", start: day(2027, 6, 1), end: day(2028, 5, 31),
                  kcal: 2500...2700, protein: 140...160, focus: "Lean gain, ~0.5 kg a month. 4 lifting days.",
                  exit: [
                      Criterion(id: "p2_weight", title: "+5–8 kg, waist up ≤ 2–3 cm", check: .manual),
                      Criterion(id: "p2_pullups", title: "10–12 strict pull-ups", check: .milestone("pullup_10")),
                      Criterion(id: "p2_dips", title: "15+ dips", check: .milestone("dips_15")),
                      Criterion(id: "p2_muscleup", title: "First muscle-up", check: .milestone("muscleup_1")),
                      Criterion(id: "p2_shoulders", title: "Visible shoulder width change in photos", check: .manual),
                  ]),
            Phase(id: "reveal", name: "Reveal", start: day(2028, 6, 1), end: day(2029, 11, 30),
                  kcal: 2000...2300, protein: 140...160, focus: "8–12 week cut, then maintain. Race.",
                  exit: [
                      Criterion(id: "p3_abs", title: "Visible abs in morning photo", check: .manual),
                      Criterion(id: "p3_10k", title: "Race a 10K", check: .milestone("run_10k_race")),
                      Criterion(id: "p3_hyrox", title: "Race an official HYROX", check: .milestone("hyrox_race")),
                      Criterion(id: "p3_strength", title: "Strength held through the cut", check: .manual),
                  ]),
        ]
    }

    static func phase(on date: Date) -> Phase {
        phases.first { date >= $0.start && date < endOfDay($0.end) } ?? (date < phases[0].start ? phases[0] : phases[phases.count - 1])
    }

    // MARK: Blocks (where I'm training)

    enum BlockKind: String, Sendable { case bali, travel, india }

    struct Block: Identifiable, Sendable {
        let id: BlockKind
        let name: String
        let start: Date
        let end: Date?
        /// Sessions a week that count as "on track".
        let weeklyTarget: Int
        let aim: String
    }

    static var blocks: [Block] {
        [
            Block(id: .bali, name: "Bali · Omni", start: dayZero, end: day(2026, 12, 2), weeklyTarget: 5,
                  aim: "Consistency and data. Log every class with its weights."),
            Block(id: .travel, name: "Travel", start: day(2026, 12, 3), end: day(2026, 12, 13), weeklyTarget: 3,
                  aim: "Don't lose ground. 3 short sessions a week, protein first."),
            Block(id: .india, name: "India", start: day(2026, 12, 14), end: nil, weeklyTarget: 5,
                  aim: "Program starts: Lift A/B/C, Friday run, Saturday HYROX."),
        ]
    }

    static func block(on date: Date) -> Block {
        blocks.last { date >= $0.start } ?? blocks[0]
    }

    // MARK: Baseline tests

    struct TestDay: Identifiable, Sendable {
        let id: String
        let date: Date
        let title: String
        let tests: [TestKind]
        let includesBody: Bool
        let includesSplits: Bool
    }

    static var testDays: [TestDay] {
        [
            TestDay(id: "run", date: day(2026, 11, 27), title: "Run", tests: [.runMeters, .runSeconds],
                    includesBody: false, includesSplits: false),
            TestDay(id: "hyrox", date: day(2026, 11, 28), title: "HYROX sim", tests: [.hyroxTotal],
                    includesBody: false, includesSplits: true),
            TestDay(id: "strength", date: day(2026, 11, 30), title: "Strength + body",
                    tests: [.pullupsMax, .deadlift5RM, .deadHang, .pushupsMax],
                    includesBody: true, includesSplits: false),
        ]
    }

    /// Tests logged on or before the last test day (plus a week's grace) are the Phase 1 baseline.
    static var baselineCutoff: Date { day(2026, 12, 7) }

    // MARK: Helpers

    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }

    /// Whole weeks from `from` to `to`, at least 0.
    static func weeks(from: Date, to: Date) -> Int {
        max(0, Int(to.timeIntervalSince(from) / (7 * 86_400)))
    }
}
