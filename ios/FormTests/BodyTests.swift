import SwiftUI
import XCTest
@testable import Form

@MainActor
final class BodyTests: XCTestCase {
    private let library = ExerciseLibrary(exercises: [
        Exercise(id: "Bench", name: "Bench Press", equipment: "barbell", primaryMuscles: ["chest"],
                 secondaryMuscles: ["triceps"], mechanic: nil, instructions: [], images: []),
        Exercise(id: "Row", name: "Barbell Row", equipment: "barbell", primaryMuscles: ["middle back"],
                 secondaryMuscles: ["biceps"], mechanic: nil, instructions: [], images: []),
        Exercise(id: "Squat", name: "Squat", equipment: "barbell", primaryMuscles: ["quadriceps"],
                 secondaryMuscles: ["glutes"], mechanic: nil, instructions: [], images: []),
    ])

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(_ ref: String, daysAgo: Double, sets: [SetKind] = [.normal, .normal, .normal]) -> WorkoutRow {
        var draft = WorkoutDraft(name: "S", startedAt: now.addingTimeInterval(-daysAgo * 86_400))
        draft.exercises = [DraftExercise(exerciseRef: ref, sets: sets.map {
            DraftSet(kind: $0, weight: 60, reps: 5, completedAt: draft.startedAt)
        })]
        draft.endedAt = draft.startedAt.addingTimeInterval(3600)
        return WorkoutStore.localRow(draft)
    }

    // MARK: Mapping

    func testEveryLibraryMuscleMapsToABodyPart() {
        let muscles = ["abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms", "glutes",
                       "hamstrings", "lats", "lower back", "middle back", "neck", "quadriceps", "shoulders", "traps", "triceps"]
        for muscle in muscles {
            XCTAssertNotNil(BodyPart(muscle: muscle), muscle)
        }
        XCTAssertEqual(BodyPart(muscle: "Middle Back"), .back)
        XCTAssertNil(BodyPart(muscle: "cardio"))
    }

    func testMapSlugs() {
        XCTAssertEqual(BodyPart(mapSlug: "deltoids"), .shoulders)
        XCTAssertEqual(BodyPart(mapSlug: "gluteal"), .legs)
        XCTAssertEqual(BodyPart(mapSlug: "upper-back"), .back)
        XCTAssertNil(BodyPart(mapSlug: "head"))
    }

    func testFreshnessThresholds() {
        XCTAssertEqual(Freshness(daysSince: 0), .fresh)
        XCTAssertEqual(Freshness(daysSince: 2), .fresh)
        XCTAssertEqual(Freshness(daysSince: 3), .recent)
        XCTAssertEqual(Freshness(daysSince: 5), .recent)
        XCTAssertEqual(Freshness(daysSince: 6), .stale)
        XCTAssertEqual(Freshness(daysSince: nil), .stale)
    }

    // MARK: Stats

    func testStatsUseLatestSessionAndSevenDayWindow() {
        let history = [
            session("Bench", daysAgo: 1),
            session("Bench", daysAgo: 4),
            session("Bench", daysAgo: 10),  // outside the window
            session("Row", daysAgo: 4, sets: [.warmup, .normal]),
        ]
        let stats = BodyStats.compute(history: history, library: library, now: now)
        XCTAssertEqual(stats[.chest]?.daysSince, 1)
        XCTAssertEqual(stats[.chest]?.recentSets, 6)
        XCTAssertEqual(stats[.chest]?.freshness, .fresh)
        XCTAssertEqual(stats[.back]?.recentSets, 1, "warmups don't count")
        XCTAssertEqual(stats[.back]?.freshness, .recent)
        XCTAssertNil(stats[.legs]?.lastTrained)
        XCTAssertEqual(stats[.legs]?.freshness, .stale)
    }

    func testWarmupOnlyExerciseDoesNotCountAsTrained() {
        let stats = BodyStats.compute(history: [session("Squat", daysAgo: 0, sets: [.warmup])], library: library, now: now)
        XCTAssertNil(stats[.legs]?.lastTrained)
    }

    func testSummaryAndLastDone() {
        let history = [session("Bench", daysAgo: 1), session("Squat", daysAgo: 3), session("Squat", daysAgo: 9)]
        let summary = BodyStats.summary(history: history, now: now)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.sets, 6)
        XCTAssertEqual(BodyStats.lastDone(history: history)["Squat"], history[1].startedAt)
    }

    // MARK: Exercise history

    func testExerciseHistoryDatesEachRecordAndFindsLastSession() {
        func lift(_ w: Double, _ r: Int, daysAgo: Double) -> WorkoutRow {
            var draft = WorkoutDraft(name: "S", startedAt: now.addingTimeInterval(-daysAgo * 86_400))
            draft.exercises = [DraftExercise(exerciseRef: "Bench", sets: [
                DraftSet(kind: .warmup, weight: 200, reps: 1, completedAt: draft.startedAt), // ignored
                DraftSet(weight: w, reps: r, completedAt: draft.startedAt),
            ])]
            draft.endedAt = draft.startedAt.addingTimeInterval(3600)
            return WorkoutStore.localRow(draft)
        }
        let history = [lift(80, 5, daysAgo: 1), lift(85, 2, daysAgo: 10), lift(60, 15, daysAgo: 30)]
        let h = Records.history(for: "Bench", in: history)
        XCTAssertEqual(h.sessions, 3)
        XCTAssertEqual(h.heaviest?.value, 85)
        XCTAssertEqual(h.heaviest?.date, history[1].startedAt)
        XCTAssertEqual(h.mostReps?.value, 15)
        XCTAssertEqual(h.mostReps?.date, history[2].startedAt)
        XCTAssertEqual(h.lastSession?.date, history[0].startedAt)
        XCTAssertEqual(h.lastSession?.sets.count, 1, "warmups excluded")
        XCTAssertNil(h.longestHold)
    }

    func testHoldHistoryUsesSeconds() {
        var draft = WorkoutDraft(name: "S", startedAt: now)
        draft.exercises = [DraftExercise(exerciseRef: "Plank", sets: [
            DraftSet(weight: 0, reps: 0, completedAt: now, durationSeconds: 45),
            DraftSet(weight: 0, reps: 0, completedAt: now, durationSeconds: 70),
        ])]
        draft.endedAt = now.addingTimeInterval(600)
        let h = Records.history(for: "Plank", in: [WorkoutStore.localRow(draft)])
        XCTAssertEqual(h.longestHold?.value, 70)
        XCTAssertNil(h.heaviest, "no added weight")
    }

    // MARK: Artwork

    func testSVGParserHandlesRelativeCommandsAndArcs() {
        let square = SVGPath.parse("M10 10h20v20h-20z").boundingRect
        XCTAssertEqual(square, CGRect(x: 10, y: 10, width: 20, height: 20))
        let compact = SVGPath.parse("M0 0l10-5.5.5 5.5z").boundingRect
        XCTAssertEqual(compact.maxX, 10.5, accuracy: 0.001)
        XCTAssertEqual(compact.minY, -5.5, accuracy: 0.001)
        // Half circle from (0,0) to (20,0), radius 10, sweeping upward (negative y).
        let arc = SVGPath.parse("M0 0a10 10 0 0 1 20 0").boundingRect
        XCTAssertEqual(arc.width, 20, accuracy: 0.01)
        XCTAssertEqual(arc.minY, -10, accuracy: 0.05)
    }

    func testBodyMapLoadsAndRegionsSitInsideTheirFigure() throws {
        let art = try XCTUnwrap(BodyMapArtwork.load(bundle: Bundle(for: ExerciseLibrary.self)))
        let frontChest = try XCTUnwrap(art.front.first { $0.slug == "chest" }).path.boundingRect
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 724, height: 1448).contains(frontChest))
        // Both pecs present: the region is centred on the figure's midline (362).
        XCTAssertEqual(frontChest.midX, 362, accuracy: 12)
        let backGlutes = try XCTUnwrap(art.back.first { $0.slug == "gluteal" }).path.boundingRect
        XCTAssertTrue(CGRect(x: 724, y: 0, width: 724, height: 1448).contains(backGlutes))
        // Every body part shows up somewhere on the map.
        let mapped = Set((art.front + art.back).compactMap(\.bodyPart))
        XCTAssertEqual(mapped, Set(BodyPart.allCases))
    }
}
