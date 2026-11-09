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
        XCTAssertEqual(plan.title, "Fullbody")
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

    // MARK: Real Omni boards (Vision OCR output from 27 photos, Sep 25 – Nov 5 2026)

    private struct Board {
        let file: String
        let plan: BoardPlan
    }

    private lazy var boards: [Board] = {
        let url = Bundle(for: BoardScanTests.self).url(forResource: "omni-boards", withExtension: "json")!
        let raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        return raw.map { board in
            let lines = (board["lines"] as! [[Any]]).map { l in
                OCRLine(text: l[4] as! String, box: CGRect(x: l[0] as! Double, y: l[1] as! Double,
                                                           width: l[2] as! Double, height: l[3] as! Double))
            }
            return Board(file: board["file"] as! String, plan: BoardParser.parse(lines))
        }
    }()

    private func board(_ file: String) -> BoardPlan { boards.first { $0.file == file }!.plan }
    private func line(_ file: String, _ name: String) -> PlannedLine? { board(file).lines.first { $0.name == name } }

    func testEveryBoardYieldsExercises() {
        XCTAssertEqual(boards.count, 27)
        for b in boards {
            XCTAssertGreaterThanOrEqual(b.plan.lines.count, 5, b.file)
        }
    }

    func testNoBoardNoiseLeaksIntoNames() {
        let noise = ["rest", "sets", "rounds", "omni", "rowerg", "start"]
        for b in boards {
            for l in b.plan.lines {
                let words = Set(l.name.lowercased().split { !$0.isLetter }.map(String.init))
                XCTAssertTrue(words.isDisjoint(with: noise), "\(b.file): \(l.name)")
                XCTAssertFalse(l.name.hasPrefix("→") || l.name.hasPrefix("•") || l.name.hasPrefix("-"), "\(b.file): \(l.name)")
                XCTAssertNil(l.name.range(of: #"\bR\s*/\s*L\b|\bRIL\b|\(T\s*[:.\d]"#, options: .regularExpression), "\(b.file): \(l.name)")
            }
        }
    }

    func testClassTitlesAreRecognised() {
        XCTAssertEqual(board("IMG_6096.DNG").title, "Fullbody")        // read as "Fallbody_"
        XCTAssertEqual(board("IMG_6302.JPG").title, "DB Fullbody")     // not the "omni" logo
        XCTAssertEqual(board("IMG_6115.DNG").title, "Kettlebells")
        XCTAssertEqual(board("IMG_6339.JPG").title, "Coreflow")
        XCTAssertEqual(board("IMG_6744.DNG").title, "Coreflow")        // read as "Careflow"
        XCTAssertEqual(board("IMG_6107.DNG").title, "Abs & Core")
        XCTAssertEqual(board("IMG_6773.DNG").title, "Strength 101")
    }

    func testSetsDirectiveAppliesToItsBlock() {
        let press = line("IMG_6302.JPG", "DB Shoulder Press")
        XCTAssertEqual(press?.sets, 4)
        XCTAssertEqual(press?.reps, 8)
        XCTAssertEqual(press?.note, "1½ reps")
        XCTAssertEqual(press?.block, "Block A")
        XCTAssertEqual(line("IMG_6302.JPG", "DB Around the World")?.sets, 3)
    }

    func testTempoAndRepRanges() {
        XCTAssertEqual(line("IMG_6651.JPG", "DDB RDL")?.note, "tempo 1-3-1-1")
        XCTAssertEqual(line("IMG_6651.JPG", "Seated Shoulder Press")?.note, "tempo 2-1-2")
        let lunge = line("IMG_6767.DNG", "FFE Split lunges")
        XCTAssertEqual(lunge?.reps, 8)
        XCTAssertEqual(lunge?.repsMax, 10)
        XCTAssertEqual(lunge?.perSide, true)
    }

    func testTimedSchemesAndSides() {
        // "40'/10' x3, Crossbody Planted Crunch" + "Hold R/L" on the next line.
        let crunch = line("IMG_6678.JPG", "Crossbody Planted Crunch Hold")
        XCTAssertEqual(crunch?.seconds, 40)
        XCTAssertEqual(crunch?.sets, 3)
        XCTAssertEqual(crunch?.perSide, true)
        // "3 RaNOS 40 20" with no separator.
        XCTAssertEqual(line("IMG_6728.DNG", "Abdominal Crunch")?.seconds, 40)
    }

    func testDittoLinesBecomeVariants() {
        // "Weighted Side Bend Crunch R/L" / "____ Hold R/L" / "____ Pulse R/L"
        let names = board("IMG_6339.JPG").lines.map(\.name)
        XCTAssertTrue(names.contains("Weighted Side Bend Crunch"))
        XCTAssertTrue(names.contains("Weighted Side Bend Crunch Hold"))
        XCTAssertTrue(names.contains("Weighted Side Bend Crunch Pulse"))
        XCTAssertFalse(names.contains("Hold"))
    }

    func testCleaningOCRSlips() {
        XCTAssertEqual(BoardParser.clean("→ 12 DDB RDL"), "12 DDB RDL")
        XCTAssertEqual(BoardParser.clean("A1. 8/Side Crossbody RDL"), "8/Side Crossbody RDL")
        XCTAssertEqual(BoardParser.clean("1D Heavy Goblet Squat"), "10 Heavy Goblet Squat")
        XCTAssertEqual(BoardParser.clean("30 / ló x3"), "30 / 10 x3")
        XCTAssertEqual(BoardParser.clean("Воск B"), "Bock B")
        XCTAssertEqual(BoardParser.parseLine("8-10 Push Ups - Rest ->").name, "Push Ups")
        XCTAssertEqual(BoardParser.parseLine("DB Low to High ChopR/L").name, "DB Low to High Chop")
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
