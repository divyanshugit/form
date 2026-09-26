import XCTest
@testable import Form

@MainActor
final class BenchmarkTests: XCTestCase {
    private let library = ExerciseLibrary(exercises: Exercise.extras + [
        Exercise(id: "Pullups", name: "Pullups", equipment: "bodyweight", primaryMuscles: ["lats"],
                 secondaryMuscles: [], mechanic: nil, instructions: [], images: []),
        Exercise(id: "Plank", name: "Plank", equipment: "bodyweight", primaryMuscles: ["abdominals"],
                 secondaryMuscles: [], mechanic: nil, instructions: [], images: []),
    ])

    private func tempStore() -> DraftStore {
        DraftStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func session(_ ref: String, _ sets: [DraftSet], daysAgo: Double) -> WorkoutRow {
        var draft = WorkoutDraft(name: ref, startedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
        draft.exercises = [DraftExercise(exerciseRef: ref, sets: sets.map { var s = $0; s.completedAt = draft.startedAt; return s })]
        return WorkoutStore.localRow(draft)
    }

    func testMetrics() {
        XCTAssertEqual(library.metric("Dead_Hang"), .duration)
        XCTAssertEqual(library.metric("Plank"), .duration)
        XCTAssertEqual(library.metric("Pullups"), .bodyweightReps)
        XCTAssertEqual(library.metric("Unknown_Custom"), .weightReps)
    }

    func testBundledLibraryIncludesHolds() {
        XCTAssertNotNil(ExerciseLibrary.shared.exercise("Dead_Hang"))
        XCTAssertNotNil(ExerciseLibrary.shared.exercise("Plank"))
    }

    func testHoldStopwatchWritesSeconds() {
        let hang = library.exercise("Dead_Hang")!
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Grip", startedAt: .now), store: tempStore(), library: library) { _ in nil }
        workout.addExercise(hang)
        XCTAssertEqual(workout.focusedSet?.durationSeconds, 30, "first-time holds start at 30s")
        let start = Date()
        workout.toggleHold(now: start)
        XCTAssertEqual(workout.holdElapsed(at: start.addingTimeInterval(12)), 12)
        workout.toggleHold(now: start.addingTimeInterval(72.4))
        XCTAssertEqual(workout.focusedSet?.durationSeconds, 72)
        XCTAssertNil(workout.holdStartedAt)
    }

    func testCompletingWhileHoldingStopsTheClock() {
        let hang = library.exercise("Dead_Hang")!
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Grip", startedAt: .now), store: tempStore(), library: library) { _ in nil }
        workout.addExercise(hang)
        let start = Date()
        workout.toggleHold(now: start)
        workout.completeFocusedSet(now: start.addingTimeInterval(45))
        XCTAssertEqual(workout.draft.exercises[0].sets[0].durationSeconds, 45)
        XCTAssertTrue(workout.draft.exercises[0].sets[0].isDone)
    }

    func testDurationSurvivesRowsRoundTrip() {
        var draft = WorkoutDraft(name: "Grip", startedAt: .now)
        draft.exercises = [DraftExercise(exerciseRef: "Dead_Hang", sets: [DraftSet(weight: 0, reps: 0, completedAt: .now, durationSeconds: 65)])]
        XCTAssertEqual(draft.rows().sets.first?.durationSeconds, 65)
    }

    func testLongestHoldIsAPR() {
        let history = [session("Dead_Hang", [DraftSet(weight: 0, reps: 0, durationSeconds: 60)], daysAgo: 7)]
        var draft = WorkoutDraft(name: "Grip", startedAt: .now)
        draft.exercises = [DraftExercise(exerciseRef: "Dead_Hang", sets: [DraftSet(weight: 0, reps: 0, completedAt: .now, durationSeconds: 75)])]
        let records = Records.newRecords(in: draft, history: history, metric: { [library] in library.metric($0) })
        XCTAssertEqual(records.first?.kind, .longestHold)
        XCTAssertEqual(records.first?.durationSeconds, 75)
    }

    func testMostRepsIsAPR() {
        let history = [session("Pullups", [DraftSet(weight: 0, reps: 10)], daysAgo: 3)]
        var draft = WorkoutDraft(name: "Pull", startedAt: .now)
        draft.exercises = [DraftExercise(exerciseRef: "Pullups", sets: [DraftSet(weight: 0, reps: 12, completedAt: .now)])]
        let records = Records.newRecords(in: draft, history: history, metric: { [library] in library.metric($0) })
        XCTAssertEqual(records.first?.kind, .mostReps)
        XCTAssertEqual(records.first?.reps, 12)
    }

    func testTrendIsBestPerSessionOldestFirst() {
        let history = [
            session("Plank", [DraftSet(weight: 0, reps: 0, durationSeconds: 90), DraftSet(weight: 0, reps: 0, durationSeconds: 60)], daysAgo: 1),
            session("Plank", [DraftSet(weight: 0, reps: 0, durationSeconds: 45)], daysAgo: 10),
        ]
        let trend = Records.trend(for: "Plank", metric: .duration, in: history)
        XCTAssertEqual(trend.map(\.value), [45, 90])
    }

    func testFormatting() {
        XCTAssertEqual(SetFormat.clock(65), "1:05")
        XCTAssertEqual(SetFormat.describe(weight: 0, reps: 12, duration: nil, metric: .bodyweightReps), "12 reps")
        XCTAssertEqual(SetFormat.describe(weight: 10, reps: 6, duration: nil, metric: .bodyweightReps), "+10 kg × 6")
        XCTAssertEqual(SetFormat.describe(weight: 0, reps: 0, duration: 72, metric: .duration), "1:12")
        XCTAssertEqual(SetFormat.describe(weight: 82.5, reps: 8, duration: nil, metric: .weightReps), "82.5 × 8")
    }

    func testQuickLogSavesOfflineFirst() async {
        let repo = MockWorkoutRepository()
        repo.failSaves = true
        let store = WorkoutStore(repository: repo, store: tempStore(), library: library)
        var draft = WorkoutDraft(name: "Dead Hang", startedAt: Date(timeIntervalSinceNow: -3600))
        draft.exercises = [DraftExercise(exerciseRef: "Dead_Hang", sets: [DraftSet(weight: 0, reps: 0, completedAt: draft.startedAt, durationSeconds: 80)])]
        await store.logManual(draft)
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.pendingCount, 1)
        repo.failSaves = false
        await store.syncPending()
        XCTAssertEqual(repo.workouts.first?.sortedExercises.first?.sortedSets.first?.durationSeconds, 80)
    }

    func testOldDraftJSONWithoutDurationStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"normal","weight":80,"reps":8}"#
        let set = try JSONDecoder().decode(DraftSet.self, from: Data(json.utf8))
        XCTAssertNil(set.durationSeconds)
    }
}
