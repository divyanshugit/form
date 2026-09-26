import XCTest
@testable import Form

final class WhoopMatchingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func whoop(_ id: String = UUID().uuidString, start: TimeInterval, minutes: Double,
                       strain: Double = 12, scored: Bool = true, sport: String = "weightlifting") -> WhoopWorkout {
        WhoopWorkout(id: id, start: t0 + start, end: t0 + start + minutes * 60, sportName: sport,
                     scoreState: scored ? .scored : .pendingScore,
                     score: scored ? .init(strain: strain, averageHeartRate: 130, maxHeartRate: 170, kilojoule: 1700) : nil)
    }

    private func session(start: TimeInterval, minutes: Double, whoopID: String? = nil) -> WorkoutRow {
        WorkoutRow(id: UUID(), name: "Push", startedAt: t0 + start, endedAt: t0 + start + minutes * 60, whoopWorkoutId: whoopID)
    }

    func testAttachesOverlappingWorkout() {
        let form = session(start: 0, minutes: 60)
        let w = whoop(start: 300, minutes: 55)
        let plan = WhoopMatching.plan(formWorkouts: [form], whoop: [w])
        XCTAssertEqual(plan.attach.count, 1)
        XCTAssertEqual(plan.attach.first?.workoutID, form.id)
        XCTAssertTrue(plan.imports.isEmpty)
    }

    func testImportsNonOverlappingWorkout() {
        let form = session(start: 0, minutes: 60)
        let run = whoop(start: 86_400, minutes: 30, sport: "running")
        let plan = WhoopMatching.plan(formWorkouts: [form], whoop: [run])
        XCTAssertTrue(plan.attach.isEmpty)
        XCTAssertEqual(plan.imports.map(\.id), [run.id])
        XCTAssertEqual(WorkoutRow.imported(from: run)?.name, "Running")
        XCTAssertEqual(WorkoutRow.imported(from: run)?.kcal, 406)
    }

    func testSmallOverlapIsNotAMatch() {
        let form = session(start: 0, minutes: 60)
        let w = whoop(start: 3300, minutes: 60) // only 5 minutes overlap
        let plan = WhoopMatching.plan(formWorkouts: [form], whoop: [w])
        XCTAssertTrue(plan.attach.isEmpty)
        XCTAssertEqual(plan.imports.count, 1)
    }

    func testPendingScoresWait() {
        let plan = WhoopMatching.plan(formWorkouts: [session(start: 0, minutes: 60)], whoop: [whoop(start: 0, minutes: 60, scored: false)])
        XCTAssertTrue(plan.attach.isEmpty)
        XCTAssertTrue(plan.imports.isEmpty)
    }

    func testAlreadyAttachedAndAlreadyImportedAreSkipped() {
        let attached = whoop(start: 0, minutes: 60)
        let imported = whoop(start: 90_000, minutes: 40, sport: "running")
        let importedRow = WorkoutRow.imported(from: imported)!
        let plan = WhoopMatching.plan(
            formWorkouts: [session(start: 0, minutes: 60, whoopID: attached.id), importedRow],
            whoop: [attached, imported]
        )
        XCTAssertTrue(plan.attach.isEmpty)
        XCTAssertTrue(plan.imports.isEmpty)
    }

    func testLoggedSessionReplacesEarlierImport() {
        // WHOOP synced before the Form session was saved, so it was imported on its own first.
        let w = whoop(start: 0, minutes: 60)
        let importedRow = WorkoutRow.imported(from: w)!
        let form = session(start: 120, minutes: 58)
        let plan = WhoopMatching.plan(formWorkouts: [form, importedRow], whoop: [w])
        XCTAssertEqual(plan.attach.first?.workoutID, form.id)
        XCTAssertEqual(plan.removeImported, [importedRow.id])
        XCTAssertTrue(plan.imports.isEmpty)
    }

    func testDecodesWhoopPayload() throws {
        let json = """
        {"records":[{"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","v1_id":1043,"user_id":9012,
        "created_at":"2026-09-26T07:02:11.101Z","updated_at":"2026-09-26T07:02:11.101Z",
        "start":"2026-09-26T05:58:00.000Z","end":"2026-09-26T06:57:00.000Z","timezone_offset":"+05:30",
        "sport_name":"weightlifting","score_state":"SCORED",
        "score":{"strain":14.2,"average_heart_rate":131,"max_heart_rate":171,"kilojoule":1724.5,
        "percent_recorded":100,"zone_durations":{"zone_zero_milli":0}}}],"next_token":null}
        """
        let page = try JSONDecoder.whoop.decode(WhoopPage<WhoopWorkout>.self, from: Data(json.utf8))
        XCTAssertEqual(page.records.first?.score?.strain, 14.2)
        XCTAssertEqual(page.records.first?.kcal, 412)
        XCTAssertNil(page.nextToken)
    }

    func testRecoveryTone() {
        XCTAssertEqual(RecoveryTone(score: 82).headline, "You're charged.")
        XCTAssertEqual(RecoveryTone(score: 50).headline, "Steady.")
        XCTAssertEqual(RecoveryTone(score: 20).headline, "Low battery.")
    }
}
