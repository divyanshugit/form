import XCTest
@testable import Form

final class ProgressLogicTests: XCTestCase {
    private let day = 86_400.0
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Makassar")!
        return c
    }()

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func session(_ name: String = "Session", at start: Date, minutes: Double = 60,
                         _ lifts: [(String, [(Double, Int, Int?)])] = [], distance: Double? = nil,
                         strain: Double? = nil, zones: [Int]? = nil) -> WorkoutRow {
        var draft = WorkoutDraft(name: name, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60))
        draft.exercises = lifts.map { ref, sets in
            DraftExercise(exerciseRef: ref, sets: sets.map { DraftSet(weight: $0.0, reps: $0.1, completedAt: start, durationSeconds: $0.2) })
        }
        var row = WorkoutStore.localRow(draft)
        row.distanceM = distance
        row.strain = strain
        row.zoneMs = zones
        return row
    }

    private let metric: Records.MetricLookup = { ref in
        switch ref {
        case "Pullups", "Pushups", "Dips_-_Triceps_Version", "Pullup_Negative": .bodyweightReps
        case "L_Sit", "Tuck_L_Sit", "Dead_Hang": .duration
        default: .weightReps
        }
    }

    // MARK: WHOOP zones

    func testWhoopWorkoutDecodesZonesAndDistance() throws {
        let json = """
        {"id":"4b0a7c46-0000-4000-8000-000000000001","start":"2026-11-07T00:32:00.000Z","end":"2026-11-07T01:40:00.000Z",
         "sport_name":"functional-fitness","score_state":"SCORED",
         "score":{"strain":15.2,"average_heart_rate":148,"max_heart_rate":186,"kilojoule":3100,"distance_meter":0,
                  "zone_durations":{"zone_zero_milli":60000,"zone_one_milli":300000,"zone_two_milli":900000,
                                    "zone_three_milli":1200000,"zone_four_milli":1100000,"zone_five_milli":420000}}}
        """
        let workout = try JSONDecoder.whoop.decode(WhoopWorkout.self, from: Data(json.utf8))
        XCTAssertEqual(workout.zoneMs, [60000, 300000, 900000, 1200000, 1100000, 420000])
        XCTAssertNil(workout.distanceM, "0 m isn't a distance")
        XCTAssertEqual(WorkoutRow.imported(from: workout)?.zoneMs?.count, 6)
    }

    func testMatchingEnrichesLinkedSessionsMissingZones() throws {
        let id = "4b0a7c46-0000-4000-8000-000000000002"
        let json = """
        {"id":"\(id)","start":"2026-11-06T22:30:00Z","end":"2026-11-06T23:10:00Z","sport_name":"running","score_state":"SCORED",
         "score":{"strain":11,"average_heart_rate":150,"max_heart_rate":175,"kilojoule":1800,"distance_meter":6120,
                  "zone_durations":{"zone_zero_milli":0,"zone_one_milli":0,"zone_two_milli":1000,"zone_three_milli":2000,"zone_four_milli":0,"zone_five_milli":0}}}
        """
        let whoop = try JSONDecoder.whoop.decode(WhoopWorkout.self, from: Data(json.utf8))
        let imported = WorkoutRow.imported(from: whoop)!
        var old = imported
        old.zoneMs = nil
        old.distanceM = nil
        let plan = WhoopMatching.plan(formWorkouts: [old], whoop: [whoop])
        XCTAssertEqual(plan.update.map(\.workoutID), [old.id])
        XCTAssertTrue(plan.imports.isEmpty)
        XCTAssertTrue(WhoopMatching.plan(formWorkouts: [imported], whoop: [whoop]).update.isEmpty)
    }

    // MARK: Milestones

    func testPullupMilestonesTickFromSets() {
        let history = [
            session(at: date("2026-11-10T08:00:00Z"), [("Pullup_Negative", [(0, 5, nil), (0, 5, nil), (0, 5, nil)])]),
            session(at: date("2026-11-20T08:00:00Z"), [("Pullups", [(0, 1, nil), (0, 2, nil)])]),
        ]
        let statuses = Milestones.evaluate(history: history, metrics: [])
        func status(_ id: String) -> Milestones.Status { statuses.first { $0.id == id }! }
        XCTAssertEqual(status("pullup_neg_3x5").achievedOn, date("2026-11-10T08:00:00Z"))
        XCTAssertEqual(status("pullup_1").achievedOn, date("2026-11-20T08:00:00Z"))
        XCTAssertNil(status("pullup_5").achievedOn)
        XCTAssertEqual(status("pullup_5").progress!, 0.4, accuracy: 0.001)
        XCTAssertEqual(status("pullup_5").best, "Best 2 reps")
        XCTAssertEqual(Milestones.nextUp(statuses).first?.id, "pullup_5")
    }

    func testBackfilledZeroKgDeadliftsNeverTickWeightMilestones() {
        let history = [session(at: date("2026-10-01T08:00:00Z"), [("Barbell_Deadlift", [(0, 10, nil)])])]
        let statuses = Milestones.evaluate(history: history, metrics: [])
        XCTAssertNil(statuses.first { $0.id == "dl_70" }!.achievedOn)
        XCTAssertNil(statuses.first { $0.id == "dl_1_5bw" }!.achievedOn)
    }

    func testBodyweightMultipleUsesWeightOnTheDay() {
        let history = [session(at: date("2026-12-20T08:00:00Z"), [("Barbell_Deadlift", [(110, 3, nil)])])]
        let light = [MetricRow(recordedAt: date("2026-12-19T00:00:00Z"), kind: MetricKind.weight, value: 72)]
        let heavy = [MetricRow(recordedAt: date("2026-12-19T00:00:00Z"), kind: MetricKind.weight, value: 75)]
        XCTAssertNotNil(Milestones.evaluate(history: history, metrics: light).first { $0.id == "dl_1_5bw" }!.achievedOn)
        XCTAssertNil(Milestones.evaluate(history: history, metrics: heavy).first { $0.id == "dl_1_5bw" }!.achievedOn)
    }

    func testRunMilestonesUseWhoopDistanceAndIgnoreWalks() {
        let history = [
            session("Walking", at: date("2026-11-01T08:00:00Z"), distance: 9000),
            session("Running", at: date("2026-11-06T22:30:00Z"), distance: 6050),
        ]
        let statuses = Milestones.evaluate(history: history, metrics: [])
        XCTAssertNotNil(statuses.first { $0.id == "run_6k" }!.achievedOn)
        XCTAssertNil(statuses.first { $0.id == "run_8k" }!.achievedOn)
    }

    func testManualTickAndHyroxSession() {
        let tick = MetricRow(recordedAt: date("2026-11-11T00:00:00Z"), kind: MetricKind.milestone("muscleup_1"), value: 1)
        let history = [session(SessionNaming.hyroxSim, at: date("2026-11-07T00:32:00Z"))]
        let statuses = Milestones.evaluate(history: history, metrics: [tick])
        XCTAssertNotNil(statuses.first { $0.id == "muscleup_1" }!.achievedOn)
        XCTAssertNotNil(statuses.first { $0.id == "hyrox_sim" }!.achievedOn)
    }

    // MARK: Goals

    func testBlocksAndPhases() {
        XCTAssertEqual(Goals.block(on: Goals.day(2026, 11, 20)).id, .bali)
        XCTAssertEqual(Goals.block(on: Goals.day(2026, 12, 5)).id, .travel)
        XCTAssertEqual(Goals.block(on: Goals.day(2026, 12, 20)).id, .india)
        XCTAssertEqual(Goals.phase(on: Goals.day(2026, 11, 20)).id, "foundation")
        XCTAssertEqual(Goals.phase(on: Goals.day(2027, 8, 1)).id, "build")
        XCTAssertEqual(Goals.phase(on: Goals.day(2028, 7, 1)).id, "reveal")
    }

    func testScheduleFollowsTheBlock() {
        let cal = Calendar.current
        // Mon Dec 14 2026 in India → Lift A; Sat → HYROX; Mon Nov 16 in Bali → Omni class.
        XCTAssertEqual(Program.planned(on: Goals.day(2026, 12, 14), calendar: cal), .liftA)
        XCTAssertEqual(Program.planned(on: Goals.day(2026, 12, 19), calendar: cal), .hyroxSim)
        XCTAssertEqual(Program.planned(on: Goals.day(2026, 11, 16), calendar: cal), .omniClass)
        XCTAssertEqual(Program.planned(on: Goals.day(2026, 12, 7), calendar: cal), .travel)
        XCTAssertEqual(Program.addOn(on: Goals.day(2026, 11, 16), calendar: cal), .afterClass)
        XCTAssertNil(Program.addOn(on: Goals.day(2026, 12, 14), calendar: cal))
    }

    func testEveryTemplateExerciseExists() {
        for template in Program.templates.values {
            for slot in template.slots {
                XCTAssertNotNil(ExerciseLibrary.shared.exercise(slot.ref), "\(template.name): \(slot.ref)")
            }
        }
        for milestone in Milestones.all {
            if case let .reps(refs, _, _, _) = milestone.rule {
                for ref in refs { XCTAssertNotNil(ExerciseLibrary.shared.exercise(ref), ref) }
            }
        }
    }

    // MARK: Double progression

    private func sets(_ weight: Double, _ reps: [Int]) -> [SetRow] {
        reps.enumerated().map { SetRow(id: UUID(), workoutExerciseId: UUID(), position: $0.offset, kind: .normal,
                                        weightKg: weight, reps: $0.element) }
    }

    func testTopOfRangeOnEverySetAddsWeight() {
        let slot = Program.Slot(ref: "Barbell_Squat", sets: 3, repMin: 8, repMax: 12)
        let up = Program.target(for: slot, metric: .weightReps, kind: .barbell, last: sets(60, [12, 12, 12]))
        XCTAssertEqual(up.weight, 62.5)
        XCTAssertEqual(up.reps, 8)
        XCTAssertNotNil(up.reason)

        let dumbbell = Program.target(for: slot, metric: .weightReps, kind: .dumbbell, last: sets(20, [12, 12, 12]))
        XCTAssertEqual(dumbbell.weight, 22)
    }

    func testShortOfTheTopKeepsWeightAndAddsARep() {
        let slot = Program.Slot(ref: "Barbell_Squat", sets: 3, repMin: 8, repMax: 12)
        let same = Program.target(for: slot, metric: .weightReps, kind: .barbell, last: sets(60, [12, 11, 9]))
        XCTAssertEqual(same.weight, 60)
        XCTAssertEqual(same.reps, 10)
        XCTAssertNil(same.reason)
        // Two sets only, even at the top: not every set.
        XCTAssertEqual(Program.target(for: slot, metric: .weightReps, kind: .barbell, last: sets(60, [12, 12])).weight, 60)
    }

    func testHoldsProgressByFiveSeconds() {
        let slot = Program.Slot(ref: "Tuck_L_Sit", sets: 3, repMin: 0, repMax: 0, seconds: 15)
        let held = (0..<3).map { SetRow(id: UUID(), workoutExerciseId: UUID(), position: $0, kind: .normal,
                                        weightKg: 0, reps: 0, durationSeconds: 16) }
        XCTAssertEqual(Program.target(for: slot, metric: .duration, kind: .bodyweight, last: held).seconds, 21)
        XCTAssertEqual(Program.target(for: slot, metric: .duration, kind: .bodyweight, last: nil).seconds, 15)
    }

    // MARK: Momentum

    func testPREventsSkipFirstSessions() {
        let history = [
            session(at: date("2026-11-01T08:00:00Z"), [("Barbell_Squat", [(50, 8, nil)])]),
            session(at: date("2026-11-08T08:00:00Z"), [("Barbell_Squat", [(50, 8, nil)])]),
            session(at: date("2026-11-15T08:00:00Z"), [("Barbell_Squat", [(55, 8, nil)]), ("Pullups", [(0, 1, nil)])]),
        ]
        let events = Momentum.prEvents(history: history, metric: metric)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.ref, "Barbell_Squat")
    }

    func testWeeklyStreakCountsWeeksHittingTarget() {
        // Two full Bali weeks with 5 training days, then this week with 2 so far (not broken yet).
        let monday = Goals.day(2026, 11, 2)
        var history: [WorkoutRow] = []
        for week in 0..<2 {
            for d in 0..<5 {
                history.append(session(at: monday.addingTimeInterval(Double(week * 7 + d) * day + 9 * 3600)))
            }
        }
        let thisMonday = monday.addingTimeInterval(14 * day)
        history.append(session(at: thisMonday.addingTimeInterval(9 * 3600)))
        history.append(session(at: thisMonday.addingTimeInterval(day + 9 * 3600)))
        let streak = Momentum.weeklyStreak(history: history, now: thisMonday.addingTimeInterval(2 * day + 12 * 3600), calendar: .current)
        XCTAssertEqual(streak.weeks, 2)
        XCTAssertEqual(streak.thisWeek, 2)
        XCTAssertEqual(streak.target, 5)

        // A week with 4 days breaks it.
        let broken = history.filter { $0.startedAt < monday.addingTimeInterval(7 * day) || $0.startedAt > monday.addingTimeInterval(8 * day) }
        XCTAssertEqual(Momentum.weeklyStreak(history: broken, now: thisMonday.addingTimeInterval(2 * day), calendar: .current).weeks, 0)
    }

    func testWalksDontCount() {
        var walk = session("Walking", at: date("2026-11-08T10:00:00Z"))
        walk.whoopWorkoutId = walk.id.uuidString.lowercased()
        XCTAssertEqual(Momentum.sinceDayOne(history: [walk], metric: metric).sessions, 0)
    }

    func testDailyStreakAllowsOneGraceDayPerWeek() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Goals.day(2026, 11, 20)) // Friday
        func d(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }
        // Fri, Thu, (Wed missed), Tue, Mon → 4, with the Wednesday as the grace day.
        XCTAssertEqual(Momentum.dailyStreak(days: [d(0), d(1), d(3), d(4)], now: today, calendar: cal), 4)
        // Two misses in the same week stop it.
        XCTAssertEqual(Momentum.dailyStreak(days: [d(0), d(3), d(4)], now: today, calendar: cal), 1)
        // Today not checked in yet doesn't break it.
        XCTAssertEqual(Momentum.dailyStreak(days: [d(1), d(2)], now: today, calendar: cal), 2)
    }

    func testWeekSummaryHardMinutes() {
        let start = Goals.day(2026, 11, 2).addingTimeInterval(9 * 3600)
        let history = [session("Running", at: start, zones: [0, 0, 0, 0, 600_000, 120_000])]
        let week = Momentum.week(containing: start, history: history, metric: metric)
        XCTAssertEqual(week.hardMinutes, 12)
        XCTAssertEqual(week.sessions.count, 1)
    }

    // MARK: Rules

    private func weights(from start: Date, days: Int, kgPerDay: Double, base: Double) -> [(date: Date, value: Double)] {
        (0..<days).map { (start.addingTimeInterval(Double($0) * day), base + kgPerDay * Double($0)) }
    }

    func testFastWeightGainSuggestsFewerCalories() {
        let now = date("2026-12-31T08:00:00Z")
        let input = Rules.Input(now: now, history: [],
                                weights: weights(from: now.addingTimeInterval(-40 * day), days: 41, kgPerDay: 0.06, base: 70),
                                waists: [], metric: metric)
        XCTAssertEqual(Rules.weeklyReview(input).first?.kind, .dropCalories)
    }

    func testFlatWeightAndStalledLiftsSuggestMoreFood() {
        let now = date("2026-12-31T08:00:00Z")
        let history = (0..<8).map { i in
            session(at: now.addingTimeInterval(-Double(i) * 2.5 * day), [("Barbell_Squat", [(60, 8, nil)])])
        }
        let input = Rules.Input(now: now, history: history,
                                weights: weights(from: now.addingTimeInterval(-40 * day), days: 41, kgPerDay: 0, base: 72),
                                waists: [(now.addingTimeInterval(-3 * day), 78)], metric: metric)
        let kinds = Rules.weeklyReview(input).map(\.kind)
        XCTAssertTrue(kinds.contains(.addCalories))
        XCTAssertTrue(kinds.contains(.review))
        XCTAssertFalse(kinds.contains(.keepGoing))
    }

    func testStrengthUpAndWaistSteadyKeepsGoing() {
        let now = date("2026-12-31T08:00:00Z")
        let history = [
            session(at: now.addingTimeInterval(-20 * day), [("Barbell_Squat", [(60, 8, nil)])]),
            session(at: now.addingTimeInterval(-3 * day), [("Barbell_Squat", [(62.5, 8, nil)])]),
        ]
        let input = Rules.Input(now: now, history: history,
                                weights: [(now.addingTimeInterval(-day), 72)],
                                waists: [(now.addingTimeInterval(-30 * day), 79), (now.addingTimeInterval(-2 * day), 78.5)],
                                metric: metric)
        XCTAssertEqual(Rules.weeklyReview(input).first?.kind, .keepGoing)
    }

    func testMissingMeasurementsAsksToWeighIn() {
        let input = Rules.Input(now: .now, history: [], weights: [], waists: [], metric: metric)
        XCTAssertEqual(Rules.weeklyReview(input).map(\.kind), [.measure])
    }

    func testDeloadAfterSevenWeeks() {
        let now = date("2026-11-20T08:00:00Z")
        let history = [session(at: date("2026-09-27T08:00:00Z")), session(at: now.addingTimeInterval(-day))]
        let input = Rules.Input(now: now, history: history, weights: [], waists: [], metric: metric)
        XCTAssertEqual(Rules.deload(input)?.kind, .deload)
        var rested = input
        rested.lastDeload = now.addingTimeInterval(-14 * day)
        XCTAssertNil(Rules.deload(rested))
    }

    func testReadiness() {
        XCTAssertEqual(Rules.readiness(recovery: 82, soreness: 1, yesterdayStrain: 8), .push)
        XCTAssertEqual(Rules.readiness(recovery: 82, soreness: 5, yesterdayStrain: 8), .steady)
        XCTAssertEqual(Rules.readiness(recovery: 30, soreness: 2, yesterdayStrain: nil), .ease)
        XCTAssertEqual(Rules.readiness(recovery: nil, soreness: nil, yesterdayStrain: nil), .steady)
    }

    func testDrainingHardDays() {
        let now = date("2026-11-30T08:00:00Z")
        let fri = date("2026-11-20T22:30:00Z"), sat = date("2026-11-21T00:30:00Z")
        let history = [session("Running", at: fri), session(SessionNaming.hyroxSim, at: sat)]
        let cal = Calendar.current
        let reds = [fri, sat].map { (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0))!.addingTimeInterval(7 * 3600), 25.0) }
        let input = Rules.Input(now: now, history: history, weights: [], waists: [], recoveries: reds, metric: metric)
        XCTAssertTrue(Rules.drainingHardDays(input, calendar: cal))
    }

    // MARK: Phase progress and metrics

    func testLiftsVsBaselineAndWaist() {
        let history = [
            session(at: Goals.day(2026, 11, 30), [("Barbell_Deadlift", [(60, 5, nil)])]),
            session(at: Goals.day(2027, 1, 10), [("Barbell_Deadlift", [(70, 5, nil)])]),
        ]
        let lifts = PhaseProgress.liftsVsBaseline(history: history, cutoff: Goals.baselineCutoff)
        XCTAssertEqual(lifts.count, 1)
        XCTAssertGreaterThan(lifts[0].now, lifts[0].baseline)

        let metrics = [
            MetricRow(recordedAt: Goals.day(2026, 11, 30), kind: MetricKind.waist, value: 79),
            MetricRow(recordedAt: Goals.day(2027, 1, 10), kind: MetricKind.waist, value: 78),
        ]
        let statuses = PhaseProgress.evaluate(Goals.phases[0], milestones: [], history: history, metrics: metrics)
        XCTAssertTrue(statuses.first { $0.id == "p1_lifts" }!.met)
        XCTAssertTrue(statuses.first { $0.id == "p1_waist" }!.met)
        XCTAssertFalse(statuses.first { $0.id == "p1_10k" }!.met)
    }

    func testMovingAverageSmoothsDailyNoise() {
        let start = Goals.day(2026, 11, 1)
        let points = [70.0, 71.0, 70.0, 71.0, 70.0, 71.0, 70.0].enumerated().map { (start.addingTimeInterval(Double($0.offset) * day), $0.element) }
        let avg = MetricMath.movingAverage(points, calendar: .current)
        XCTAssertEqual(avg.count, 7)
        XCTAssertEqual(avg.last!.value, 70.4286, accuracy: 0.001)
    }

    func testTestFormatting() {
        XCTAssertEqual(TestKind.runSeconds.format(2_345), "39:05")
        XCTAssertEqual(TestKind.runMeters.format(6_500), "6.50 km")
        XCTAssertEqual(TestKind.hyroxTotal.format(5_400), "1:30:00")
        XCTAssertEqual(TestKind.deadlift5RM.format(62.5), "62.5 kg")
    }
}

final class BoardSchemeTests: XCTestCase {
    func testDescendingSchemeAndLadder() {
        let scheme = BoardParser.parseLine("15-9-6 Thrusters")
        XCTAssertEqual(scheme.name, "Thrusters")
        XCTAssertEqual(scheme.sets, 3)
        XCTAssertEqual(scheme.reps, 15)
        XCTAssertEqual(scheme.note, "15-9-6 reps")

        let ladder = BoardParser.parseLine("1-2-3-4-5 Pull-ups")
        XCTAssertEqual(ladder.name, "Pull-ups")
        XCTAssertEqual(ladder.sets, 5)
        XCTAssertEqual(ladder.note, "ladder 1-2-3-4-5 reps")
    }

    func testDistances() {
        let row = BoardParser.parseLine("500m Row")
        XCTAssertEqual(row.name, "Row")
        XCTAssertNil(row.reps)
        XCTAssertEqual(row.note, "500 m")
        XCTAssertEqual(BoardParser.parseLine("1 km Run").note, "1 km")
        XCTAssertEqual(BoardParser.parseLine("Ski Erg 250m").name, "Ski Erg")
        // Reps that happen to precede an m-word are still reps.
        XCTAssertEqual(BoardParser.parseLine("12 Mountain Climbers").reps, 12)
    }
}

final class ShareCardTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testRecapMatchesTheWeekendCard() {
        // The reference story: Fri 59:00 run of 6.04 km + Sat HYROX 1:07:58.
        var run = WorkoutRow(id: UUID(), name: "Running", startedAt: date("2026-11-05T22:31:00Z"),
                             endedAt: date("2026-11-05T23:30:00Z"), avgHr: 151, maxHr: 190)
        run.distanceM = 6040
        run.zoneMs = [60_000, 600_000, 900_000, 500_000, 1_000_000, 480_000]
        var sim = WorkoutRow(id: UUID(), name: SessionNaming.hyroxSim, startedAt: date("2026-11-07T00:32:00Z"),
                             endedAt: date("2026-11-07T01:39:58Z"), avgHr: 143, maxHr: 188)
        sim.zoneMs = [600_000, 900_000, 400_000, 500_000, 1_400_000, 278_000]

        var bali = Calendar(identifier: .gregorian)
        bali.timeZone = TimeZone(identifier: "Asia/Makassar")!
        let card = ShareCards.recap([sim, run], dayNumber: 42, name: { $0 }, calendar: bali)
        XCTAssertEqual(card.title, "Going into the weekend")
        XCTAssertTrue(card.subtitle.hasPrefix("2:07 trained"), card.subtitle)
        XCTAssertTrue(card.subtitle.contains("% in zone 4–5"))
        XCTAssertEqual(card.sections.count, 2)
        XCTAssertEqual(card.sections[0].hero, "6.04")
        XCTAssertEqual(card.sections[0].heroUnit, "km")
        XCTAssertEqual(card.sections[0].stats.map(\.value), ["59:00", "9:46", "151"])
        XCTAssertEqual(card.sections[1].hero, "1:07:58")
        XCTAssertEqual(card.combinedZones?.count, 6)
        XCTAssertEqual(card.footer, "form · day 42")
    }

    func testCardsNeverInventNumbers() {
        let plain = WorkoutRow(id: UUID(), name: "Fullbody", startedAt: date("2026-11-04T07:55:00Z"),
                               endedAt: date("2026-11-04T08:50:00Z"))
        let card = ShareCards.session(plain, dayNumber: nil, name: { $0 })
        XCTAssertNil(card.sections[0].zones)
        XCTAssertEqual(card.sections[0].stats.map(\.label), ["start"], "No heart rate without WHOOP data")
        XCTAssertEqual(card.footer, "form")
    }

    func testHyroxStationsShareTheRestOfTheRaceAsRuns() {
        // Two stations of 5 min in a 30 min race inside a 40 min session: two 10 min runs.
        let segments = ShareCards.hyroxSegments(splits: [.ski: 300, .wallBalls: 300], total: 1800, sessionSeconds: 2400)
        XCTAssertEqual(segments.map(\.label), ["RUN", "SKI", "RUN", "WB"])
        XCTAssertEqual(segments[1].start, 600.0 / 2400, accuracy: 1e-9)
        XCTAssertEqual(segments[3].end, 1800.0 / 2400, accuracy: 1e-9)
        XCTAssertTrue(ShareCards.hyroxSegments(splits: [:], total: 1800, sessionSeconds: 2400).isEmpty)
        // A race logged longer than the session is squeezed to fit.
        let squeezed = ShareCards.hyroxSegments(splits: [.row: 600], total: 3000, sessionSeconds: 2400)
        XCTAssertEqual(squeezed.last!.end, 1, accuracy: 1e-9)
    }

    func testComparesWithTheLastSessionOfTheSameName() {
        let old = WorkoutRow(id: UUID(), name: "HYROX sim", startedAt: date("2026-10-31T00:30:00Z"),
                             endedAt: date("2026-10-31T01:40:00Z"), avgHr: 164)
        let other = WorkoutRow(id: UUID(), name: "Lift A", startedAt: date("2026-11-03T00:30:00Z"),
                               endedAt: date("2026-11-03T01:30:00Z"))
        let now = WorkoutRow(id: UUID(), name: "hyrox sim", startedAt: date("2026-11-07T00:30:00Z"),
                             endedAt: date("2026-11-07T01:40:00Z"), avgHr: 158)
        let previous = ShareCards.previous(of: now, in: [old, other, now])
        XCTAssertEqual(previous?.id, old.id)
        XCTAssertTrue(ShareCards.comparisonLabel(now, previous: old).hasSuffix("avg −6 bpm"))
        XCTAssertNil(ShareCards.previous(of: old, in: [old, other, now]))
    }

    func testHighlightPicksTheFirstThingTheSessionEarned() {
        var now = WorkoutRow(id: UUID(), name: "HYROX sim", startedAt: date("2026-11-07T00:30:00Z"),
                             endedAt: date("2026-11-07T01:40:00Z"), avgHr: 158)
        now.zoneMs = [0, 0, 0, 600_000, 900_000, 300_000]
        let old = WorkoutRow(id: UUID(), name: "HYROX sim", startedAt: date("2026-10-31T00:30:00Z"),
                             endedAt: date("2026-10-31T01:40:00Z"), avgHr: 164)
        let earlierSki = MetricRow(recordedAt: old.startedAt, kind: HyroxStation.ski.metric, value: 282, workoutId: old.id)
        let todaySki = MetricRow(recordedAt: now.startedAt, kind: HyroxStation.ski.metric, value: 270, workoutId: now.id)
        let history = [old, now]

        XCTAssertEqual(ShareCards.highlight(for: now, prs: ["Deadlift"], splits: [.ski: 270], metrics: [earlierSki], history: history),
                       "PR · Deadlift")
        XCTAssertEqual(ShareCards.highlight(for: now, prs: ["Deadlift", "Row"], splits: [:], metrics: [], history: history),
                       "2 PRs today")
        XCTAssertEqual(ShareCards.highlight(for: now, prs: [], splits: [.ski: 270], metrics: [earlierSki, todaySki], history: history),
                       "Fastest SkiErg yet · 4:30, 12 s quicker")
        // A slower split than before isn't a highlight; falls through to the lower average.
        XCTAssertTrue(ShareCards.highlight(for: now, prs: [], splits: [.ski: 300], metrics: [earlierSki], history: history)?
                        .hasPrefix("Avg HR 6 bpm lower than") == true)

        // Most hard minutes in 30 days needs at least three other sessions to beat.
        let easy = (1...3).map { day -> WorkoutRow in
            var w = WorkoutRow(id: UUID(), name: "Run", startedAt: date("2026-11-0\(day)T07:00:00Z"), endedAt: date("2026-11-0\(day)T08:00:00Z"))
            w.zoneMs = [0, 0, 0, 0, 300_000, 0]
            return w
        }
        XCTAssertEqual(ShareCards.highlight(for: now, prs: [], splits: [:], metrics: [], history: easy + [now]),
                       "Most zone 4–5 time in 30 days · 20 min")
        XCTAssertNil(ShareCards.highlight(for: old, prs: [], splits: [:], metrics: [], history: [old]))
    }

    @MainActor
    func testCurvesOnOneCardShareAScale() {
        var low = ShareCardModel.Section(label: "", hero: "", curve: [120, 150, 160])
        low.peakBpm = 172
        let high = ShareCardModel.Section(label: "", hero: "", curve: [130, 185, 150])
        let range = HeartRateCurveView.range(for: [low, high], maxHR: 190)
        XCTAssertEqual(range.upperBound, 191, "highest of every curve and true peak, plus headroom")
        XCTAssertEqual(range.lowerBound, 89)
    }
}

final class HeartRateCurveTests: XCTestCase {
    /// A short spike survives in `peak` even though averaging flattens it in the curve.
    func testPeakKeepsTheSpikeTheCurveSmoothsAway() throws {
        let start = Date(timeIntervalSince1970: 0), end = start.addingTimeInterval(3600)
        var samples = stride(from: 0.0, through: 3600, by: 5).map { (date: start.addingTimeInterval($0), bpm: 170.0) }
        samples[540] = (start.addingTimeInterval(2700), 191)
        let curve = try XCTUnwrap(HeartRateCurve.resample(samples, start: start, end: end))
        XCTAssertLessThan(try XCTUnwrap(curve.max()), 185)
        let peak = try XCTUnwrap(HeartRateCurve.peak(samples, start: start, end: end))
        XCTAssertEqual(peak.bpm, 191)
        XCTAssertEqual(peak.at, 0.75, accuracy: 0.001)
    }

    func testZonesFollowWhoopPercentages() {
        XCTAssertEqual(HeartRateCurve.zone(90, maxHR: 190), 0)
        XCTAssertEqual(HeartRateCurve.zone(120, maxHR: 190), 2)
        XCTAssertEqual(HeartRateCurve.zone(160, maxHR: 190), 4)
        XCTAssertEqual(HeartRateCurve.zone(188, maxHR: 190), 5)
    }

    func testResampleFillsGapsAndRefusesSparseData() {
        let start = Date(timeIntervalSince1970: 0), end = start.addingTimeInterval(600)
        let samples = stride(from: 0.0, to: 600, by: 5).filter { !(200..<260).contains($0) }
            .map { (date: start.addingTimeInterval($0), bpm: 100 + $0 / 10) }
        let curve = try! XCTUnwrap(HeartRateCurve.resample(samples, start: start, end: end, buckets: 60))
        XCTAssertEqual(curve.count, 60)
        XCTAssertTrue(curve.allSatisfy { $0 > 99 && $0 < 161 })
        XCTAssertGreaterThan(curve[59], curve[0])
        XCTAssertNil(HeartRateCurve.resample(Array(samples.prefix(3)), start: start, end: end, buckets: 60),
                     "Three samples aren't a curve")
    }
}
