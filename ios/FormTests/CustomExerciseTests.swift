import XCTest
@testable import Form

@MainActor
final class CustomExerciseTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private let bench = Exercise(id: "Bench", name: "Bench Press", equipment: "barbell",
                                 primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
                                 mechanic: "compound",
                                 instructions: ["Lie back on a flat bench and grip the bar just wider than your shoulders. Unrack it."],
                                 images: [])

    func testGeneratedSummaryReadsLikeADescription() {
        XCTAssertEqual(bench.summary,
                       "A compound chest exercise with a barbell. Also works your triceps and shoulders. Lie back on a flat bench and grip the bar just wider than your shoulders.")
    }

    func testHoldsAreDescribedAsHolds() {
        let hang = Exercise.extras.first { $0.id == "Dead_Hang" }!
        XCTAssertTrue(hang.summary.hasPrefix("An isolation forearms hold using your bodyweight."))
    }

    func testYourDescriptionWins() {
        let row = CustomExerciseRow(id: UUID(), name: "Landmine Press", equipment: "barbell", primaryMuscle: "shoulders",
                                    metric: .weightReps, description: "One-arm press with a barbell anchored in a corner.")
        XCTAssertEqual(row.exercise.summary, "One-arm press with a barbell anchored in a corner.")
        XCTAssertTrue(row.exercise.isCustom)
        XCTAssertEqual(row.exercise.kind.barWeight, 20, "barbell customs get the loaded bar")
    }

    func testCustomMetricOverridesEquipment() {
        let row = CustomExerciseRow(id: UUID(), name: "Towel Hang", equipment: "other", primaryMuscle: "forearms",
                                    metric: .duration, description: nil)
        XCTAssertEqual(row.exercise.metric, .duration)
    }

    func testSavedExerciseIsInTheLibraryAndSyncsLater() async {
        let repo = MockCustomExerciseRepository()
        repo.failWrites = true
        let library = ExerciseLibrary(exercises: [bench])
        let store = CustomExerciseStore(repository: repo, library: library, directory: tempDir())
        let created = await store.save(CustomExerciseRow(id: UUID(), name: "Landmine Press", equipment: "barbell",
                                                          primaryMuscle: "shoulders", metric: .weightReps, description: nil))
        XCTAssertNotNil(library.exercise(created.id), "usable right away, offline")
        XCTAssertEqual(library.search("landmine").first?.id, created.id)
        XCTAssertTrue(repo.rows.isEmpty)

        repo.failWrites = false
        await store.sync()
        XCTAssertEqual(repo.rows.count, 1)
    }

    func testCustomExercisesSurviveRelaunch() async {
        let dir = tempDir()
        let library = ExerciseLibrary(exercises: [bench])
        let store = CustomExerciseStore(repository: MockCustomExerciseRepository(), library: library, directory: dir)
        let created = await store.save(CustomExerciseRow(id: UUID(), name: "Sled Push", equipment: "other",
                                                          primaryMuscle: "quadriceps", metric: .weightReps, description: nil))
        let fresh = ExerciseLibrary(exercises: [bench])
        _ = CustomExerciseStore(repository: MockCustomExerciseRepository(), library: fresh, directory: dir)
        XCTAssertEqual(fresh.exercise(created.id)?.name, "Sled Push")
    }

    func testCustomExerciseWorksInAWorkout() {
        let row = CustomExerciseRow(id: UUID(), name: "Towel Hang", equipment: "other", primaryMuscle: "forearms",
                                    metric: .duration, description: nil)
        let library = ExerciseLibrary(exercises: [])
        library.setCustom([row.exercise])
        let workout = ActiveWorkout(draft: WorkoutDraft(name: "Grip", startedAt: .now),
                                    store: DraftStore(directory: tempDir()), library: library) { _ in nil }
        workout.addExercise(row.exercise)
        XCTAssertEqual(workout.focusedSet?.durationSeconds, 30, "timed customs start with the stopwatch")
    }
}
