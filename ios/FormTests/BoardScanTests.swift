import XCTest
@testable import Form

@MainActor
final class BoardScanTests: XCTestCase {
    /// What on-device text recognition read from a real gym whiteboard (minX, midY, text).
    private let whiteboard: [(CGFloat, CGFloat, String)] = [
        (0.11, 0.36, "8/Side Uneven Stance RDL"),
        (0.11, 0.44, "15 Banded Face Pull"),
        (0.11, 0.40, "12 DB Z Press"),
        (0.14, 0.29, "Bock At"),
        (0.41, 0.22, "Fulbody"),
        (0.43, 0.57, "Banded Triceps Push Down"),
        (0.43, 0.61, "DB Hammer Curls"),
        (0.44, 0.50, "Finisher"),
        (0.47, 0.35, "8/Side Def. Split lunges"),
        (0.47, 0.29, "Block B"),
        (0.47, 0.39, "12 KB Bent Over Row"),
        (0.48, 0.43, "8 Arnold Press"),
        (0.55, 0.53, "Tabata"),
        (0.76, 0.45, "10 Heavy Goblet quat"),
        (0.76, 0.34, "10 DB Hamst. Curls"),
        (0.76, 0.38, "8 DB Front lateral"),
        (0.79, 0.40, "Raise"),
        (0.80, 0.29, "Block C"),
    ]

    private var lines: [OCRLine] {
        whiteboard.map { x, y, text in
            OCRLine(text: text, box: CGRect(x: x, y: y - 0.012, width: CGFloat(text.count) * 0.011, height: 0.024))
        }
    }

    // MARK: Parsing

    func testParsesWhiteboardIntoOrderedBlocks() {
        let plan = BoardParser.parse(lines)
        XCTAssertEqual(plan.title, "Fulbody")
        XCTAssertEqual(plan.lines.map(\.name), [
            "Uneven Stance RDL", "DB Z Press", "Banded Face Pull",
            "Def. Split lunges", "KB Bent Over Row", "Arnold Press",
            "DB Hamst. Curls", "DB Front lateral Raise", "Heavy Goblet quat",
            "Banded Triceps Push Down", "DB Hammer Curls",
        ])
        XCTAssertEqual(plan.lines.map(\.block), [
            "Block A", "Block A", "Block A", "Block B", "Block B", "Block B",
            "Block C", "Block C", "Block C", "Finisher · Tabata", "Finisher · Tabata",
        ])
        XCTAssertEqual(plan.lines[0].reps, 8)
        XCTAssertTrue(plan.lines[0].perSide)
        XCTAssertEqual(plan.lines[2].reps, 15)
        XCTAssertFalse(plan.lines[2].perSide)
        XCTAssertNil(plan.lines[9].reps)
    }

    func testRepFormats() {
        XCTAssertEqual(BoardParser.parseLine("3x10 Bench Press").sets, 3)
        XCTAssertEqual(BoardParser.parseLine("3x10 Bench Press").reps, 10)
        XCTAssertEqual(BoardParser.parseLine("Squat 5 x 5").reps, 5)
        XCTAssertEqual(BoardParser.parseLine("Squat 5 x 5").name, "Squat")
        XCTAssertEqual(BoardParser.parseLine("30s Plank").seconds, 30)
        XCTAssertEqual(BoardParser.parseLine("10 Squats").reps, 10)
        XCTAssertEqual(BoardParser.parseLine("10 Squats").name, "Squats")
        XCTAssertTrue(BoardParser.parseLine("12 each side Lunges").perSide)
        XCTAssertEqual(BoardParser.parseLine("12 each side Lunges").name, "Lunges")
    }

    // MARK: Matching

    private lazy var matcher = ExerciseMatcher(exercises: ExerciseLibrary(bundle: Bundle(for: ExerciseLibrary.self)).all)

    private func best(_ name: String) -> String? { matcher.best(for: name)?.exercise.name }

    func testMatchesCommonBoardNames() {
        XCTAssertEqual(best("Banded Face Pull"), "Face Pull")
        XCTAssertEqual(best("Heavy Goblet quat"), "Goblet Squat")
        XCTAssertEqual(best("Banded Triceps Push Down"), "Triceps Pushdown")
        XCTAssertEqual(best("DB Hammer Curls"), "Hammer Curls")
        XCTAssertEqual(best("DB Front lateral Raise"), "Front Dumbbell Raise")
        XCTAssertEqual(best("Arnold Press")?.contains("Arnold"), true)
        XCTAssertEqual(ExerciseMatcher.confidence(matcher.best(for: "Heavy Goblet quat")?.score), .confident)
    }

    func testUnknownMovesAreNotConfidentlyMatched() {
        // Not in the library: the review screen should offer to create these.
        XCTAssertNotEqual(ExerciseMatcher.confidence(matcher.best(for: "DB Z Press")?.score), .confident)
        XCTAssertNotEqual(ExerciseMatcher.confidence(matcher.best(for: "Def. Split lunges")?.score), .confident)
    }

    func testEquipmentClashIsPenalised() {
        let kbRow = ExerciseMatcher.score(query: ExerciseMatcher.tokens("KB Bent Over Row"),
                                          candidate: ExerciseMatcher.tokens("Bent Over Barbell Row"))
        let row = ExerciseMatcher.score(query: ExerciseMatcher.tokens("Bent Over Row"),
                                        candidate: ExerciseMatcher.tokens("Bent Over Barbell Row"))
        XCTAssertLessThan(kbRow, row)
    }

    func testRememberedPickWins() {
        let custom = Exercise(id: "custom:z", name: "DB Z Press", equipment: "dumbbell", primaryMuscles: ["shoulders"],
                              secondaryMuscles: [], mechanic: nil, instructions: [], images: [])
        let library = ExerciseLibrary(bundle: Bundle(for: ExerciseLibrary.self)).all + [custom]
        let m = ExerciseMatcher(exercises: library, remembered: [ExerciseMatcher.key("12 DB Z Press"): "custom:z"])
        XCTAssertEqual(m.best(for: "DB Z Press")?.exercise.id, "custom:z")
        XCTAssertEqual(m.best(for: "DB Z Press")?.score, 1)
    }
}
