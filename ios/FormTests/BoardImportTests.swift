import XCTest
@testable import Form

final class BoardImportTests: XCTestCase {
    private let bali = TimeZone(identifier: "Asia/Makassar")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func session(_ name: String, _ start: String, minutes: Double = 60, whoop: Bool = true,
                         exercises: [WorkoutExerciseRow]? = nil) -> WorkoutRow {
        let id = UUID()
        let startDate = date(start)
        return WorkoutRow(id: id, name: name, startedAt: startDate, endedAt: startDate.addingTimeInterval(minutes * 60),
                          whoopWorkoutId: whoop ? id.uuidString.lowercased() : nil, workoutExercises: exercises)
    }

    // MARK: EXIF

    func testExifDateUsesCameraOffset() {
        // IMG_6785: photographed at 15:53:43 in Bali (UTC+8).
        XCTAssertEqual(BoardImport.exifDate("2026:11:04 15:53:43", offset: "+08:00"), date("2026-11-04T07:53:43Z"))
    }

    func testExifDateFallsBackToTimeZone() {
        XCTAssertEqual(BoardImport.exifDate("2026:11:04 15:53:43", offset: nil, fallback: bali), date("2026-11-04T07:53:43Z"))
    }

    // MARK: Matching

    func testBoardMatchesTheClassItWasPhotographedBefore() {
        // Real day: an early-morning class, a walk, and the 4 pm class the board is for.
        let morning = session("Functional Fitness", "2026-11-04T00:10:00Z", minutes: 50)
        let walk = session("Walking", "2026-11-04T07:40:00Z", minutes: 20)
        let afternoon = session("Functional Fitness", "2026-11-04T07:55:00Z", minutes: 55)
        let taken = date("2026-11-04T07:53:43Z")
        XCTAssertEqual(BoardImport.session(for: taken, in: [morning, walk, afternoon])?.id, afternoon.id)
    }

    func testPrefersSessionsWithoutExercises() {
        let defined = session("DB Fullbody", "2026-11-04T07:55:00Z",
                              exercises: [WorkoutExerciseRow(id: UUID(), workoutId: UUID(), exerciseRef: "x", position: 0)])
        let empty = session("Functional Fitness", "2026-11-04T08:10:00Z")
        XCTAssertEqual(BoardImport.session(for: date("2026-11-04T07:53:00Z"), in: [defined, empty])?.id, empty.id)
    }

    func testNoMatchFarFromAnySession() {
        let afternoon = session("Functional Fitness", "2026-11-04T07:55:00Z")
        XCTAssertNil(BoardImport.session(for: date("2026-11-04T03:00:00Z"), in: [afternoon]))
    }

    // MARK: Planned sets

    private let goblet = Exercise(id: "Goblet_Squat", name: "Goblet Squat", equipment: "kettlebells",
                                  primaryMuscles: ["quadriceps"], secondaryMuscles: [], mechanic: nil, instructions: [], images: [])

    func testBackfilledSetsNeverInventAWeight() {
        let planned = BoardImport.plannedExercise(goblet, sets: 4, reps: 10, seconds: nil, note: "Block A",
                                                  at: date("2026-11-04T07:55:00Z"))
        XCTAssertEqual(planned.sets.count, 4)
        XCTAssertTrue(planned.sets.allSatisfy { $0.weight == 0 && $0.reps == 10 && $0.isDone })
        XCTAssertEqual(planned.notes, "Block A")
        XCTAssertEqual(SetFormat.describe(weight: 0, reps: 10, duration: nil, metric: .weightReps), "10 reps")
        // No rep count on the board either.
        XCTAssertEqual(SetFormat.describe(weight: 0, reps: 0, duration: nil, metric: .weightReps), "done")
    }

    func testBoardTitleReplacesWhoopSportName() {
        XCTAssertEqual(BoardImport.name(current: "Functional Fitness", original: "Functional Fitness",
                                        isWhoopImport: true, boardTitle: "DB Fullbody"), "DB Fullbody")
        // A name the user already changed stays.
        XCTAssertEqual(BoardImport.name(current: "Leg day", original: "Functional Fitness",
                                        isWhoopImport: true, boardTitle: "DB Fullbody"), "Leg day")
    }

    // MARK: Naming

    func testSaturdayMorningFunctionalFitnessIsHyroxSim() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bali
        // Sat Nov 7, 08:32 in Bali.
        XCTAssertTrue(SessionNaming.isHyroxSim(sportName: "Functional Fitness", start: date("2026-11-07T00:32:00Z"), calendar: calendar))
        // Same Saturday, 4 pm class: not the sim.
        XCTAssertFalse(SessionNaming.isHyroxSim(sportName: "Functional Fitness", start: date("2026-11-07T08:00:00Z"), calendar: calendar))
        // Friday morning, or a Saturday run.
        XCTAssertFalse(SessionNaming.isHyroxSim(sportName: "Functional Fitness", start: date("2026-11-06T00:32:00Z"), calendar: calendar))
        XCTAssertFalse(SessionNaming.isHyroxSim(sportName: "Running", start: date("2026-11-07T00:32:00Z"), calendar: calendar))
    }

    func testWalksAreHiddenUnlessDefined() {
        XCTAssertTrue(HistoryFilter.isWalk(session("Walking", "2026-11-08T10:15:00Z")))
        XCTAssertFalse(HistoryFilter.isWalk(session("Running", "2026-11-06T22:31:00Z")))
        XCTAssertFalse(HistoryFilter.isWalk(session("Walking", "2026-11-08T10:15:00Z", whoop: false)))
    }
}
