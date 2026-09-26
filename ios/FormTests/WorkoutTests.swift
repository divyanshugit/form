import XCTest
@testable import Form

@MainActor
final class WorkoutTests: XCTestCase {
    private let bench = Exercise(id: "Bench", name: "Bench Press", equipment: "barbell",
                                 primaryMuscles: ["chest"], secondaryMuscles: [], mechanic: nil,
                                 instructions: [], images: [])

    private func tempStore() -> DraftStore {
        DraftStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func historyWorkout(weight: Double, reps: Int, daysAgo: Double) -> WorkoutRow {
        var draft = WorkoutDraft(name: "Push", startedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
        draft.exercises = [DraftExercise(exerciseRef: "Bench", sets: [
            DraftSet(weight: weight, reps: reps, completedAt: draft.startedAt),
            DraftSet(weight: weight, reps: reps, completedAt: draft.startedAt),
        ])]
        draft.endedAt = draft.startedAt.addingTimeInterval(3600)
        return WorkoutStore.localRow(draft)
    }

    func testAddExercisePrefillsFromLastSession() {
        let history = [historyWorkout(weight: 80, reps: 8, daysAgo: 3)]
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: tempStore(),
                                    library: ExerciseLibrary(exercises: [bench])) {
            Records.lastSets(for: $0, in: history)
        }
        workout.addExercise(bench)
        XCTAssertEqual(workout.draft.exercises.first?.sets.map(\.weight), [80, 80])
        XCTAssertEqual(workout.focus, .init(exercise: 0, set: 0))
    }

    func testFirstTimeExerciseStartsWithEmptyBar() {
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: tempStore(),
                                    library: ExerciseLibrary(exercises: [bench])) { _ in nil }
        workout.addExercise(bench)
        XCTAssertEqual(workout.draft.exercises.first?.sets.count, 3)
        XCTAssertEqual(workout.focusedSet?.weight, 20)
    }

    func testCompletingSetAdvancesFocusAndStartsRest() {
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: tempStore(),
                                    library: ExerciseLibrary(exercises: [bench])) { _ in nil }
        workout.addExercise(bench)
        let now = Date()
        workout.completeFocusedSet(now: now)
        XCTAssertEqual(workout.focus, .init(exercise: 0, set: 1))
        XCTAssertEqual(workout.restRemaining(at: now), 120, accuracy: 0.5)
        workout.adjustRest(by: -15, now: now)
        XCTAssertEqual(workout.restRemaining(at: now), 105, accuracy: 0.5)
    }

    func testWeightChangeCarriesToLaterOpenSets() {
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: tempStore(),
                                    library: ExerciseLibrary(exercises: [bench])) { _ in nil }
        workout.addExercise(bench)
        workout.adjustWeight(by: 60)
        XCTAssertEqual(workout.draft.exercises[0].sets.map(\.weight), [80, 80, 80])
        workout.adjustWeight(by: -100)
        XCTAssertEqual(workout.focusedSet?.weight, 20, "can't go below the bar")
    }

    func testLastSetFinishesLogging() {
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: tempStore(),
                                    library: ExerciseLibrary(exercises: [bench])) { _ in nil }
        workout.addExercise(bench)
        for _ in 0..<3 { workout.completeFocusedSet() }
        XCTAssertNil(workout.focus)
        XCTAssertTrue(workout.isFinishedLogging)
        XCTAssertEqual(workout.restRemaining(at: .now), 0, "no rest after the final set")
    }

    func testActiveWorkoutSurvivesRelaunch() {
        let store = tempStore()
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Push", startedAt: .now), store: store,
                                    library: ExerciseLibrary(exercises: [bench])) { _ in nil }
        workout.addExercise(bench)
        workout.completeFocusedSet()
        let restored = store.loadActive()
        XCTAssertEqual(restored?.exercises.first?.sets.filter(\.isDone).count, 1)
        XCTAssertEqual(ActiveWorkout.firstOpenSet(in: restored!), .init(exercise: 0, set: 1))
    }

    func testRecordsDetectNewOneRepMax() {
        let history = [historyWorkout(weight: 80, reps: 8, daysAgo: 4)]
        var draft = WorkoutDraft(name: "Push", startedAt: .now)
        draft.exercises = [DraftExercise(exerciseRef: "Bench", sets: [DraftSet(weight: 82.5, reps: 8, completedAt: .now)])]
        let records = Records.newRecords(in: draft, history: history)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .estimatedOneRepMax)
    }

    func testFirstEverSessionIsNotAPR() {
        var draft = WorkoutDraft(name: "Push", startedAt: .now)
        draft.exercises = [DraftExercise(exerciseRef: "Bench", sets: [DraftSet(weight: 60, reps: 8, completedAt: .now)])]
        XCTAssertTrue(Records.newRecords(in: draft, history: []).isEmpty)
    }

    func testFinishQueuesOfflineAndSyncsLater() async {
        let repo = MockWorkoutRepository()
        repo.failSaves = true
        let store = WorkoutStore(repository: repo, store: tempStore(), library: ExerciseLibrary(exercises: [bench]))
        store.startWorkout()
        store.active?.addExercise(bench)
        store.active?.completeFocusedSet()
        let saved = await store.finishActive()
        XCTAssertNotNil(saved)
        XCTAssertNil(store.active)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.history.count, 1, "visible locally before it uploads")

        repo.failSaves = false
        await store.syncPending()
        XCTAssertEqual(store.pendingCount, 0)
        XCTAssertEqual(repo.workouts.first?.sortedExercises.first?.sets?.count, 1, "only completed sets are saved")
    }

    func testRowsOnlyIncludeCompletedSets() {
        var draft = WorkoutDraft(name: "Push", startedAt: .now)
        draft.exercises = [
            DraftExercise(exerciseRef: "Bench", sets: [DraftSet(weight: 80, reps: 8, completedAt: .now), DraftSet(weight: 80, reps: 8)]),
            DraftExercise(exerciseRef: "Fly", sets: [DraftSet(weight: 10, reps: 12)]),
        ]
        let rows = draft.rows()
        XCTAssertEqual(rows.exercises.count, 1)
        XCTAssertEqual(rows.sets.count, 1)
    }
}
