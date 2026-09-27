#if DEBUG
import Foundation
import UIKit

/// Debug-only: launch with `-demo` to skip sign-in and use sample history in memory,
/// and `-demoWorkout` to open straight into a bench session. Used for simulator screenshots.
enum DemoMode {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var opensWorkout: Bool { ProcessInfo.processInfo.arguments.contains("-demoWorkout") }
    static var opensCollage: Bool { ProcessInfo.processInfo.arguments.contains("-demoCollage") }
    static var opensHold: Bool { ProcessInfo.processInfo.arguments.contains("-demoHold") }
    /// `-demoTab 2` opens the third tab.
    static var tab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }
    /// `-demoExercise Plank` opens that exercise's detail sheet from the Body tab.
    static var exerciseID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoExercise"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @MainActor
    static func makeStore() -> WorkoutStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-demo", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let store = WorkoutStore(repository: MockWorkoutRepository(workouts: sampleHistory()),
                                 store: DraftStore(directory: directory))
        return store
    }

    /// Eight months of placeholder progress photos (drawn, not real) for screenshots.
    @MainActor
    static func makePhotoStore() -> PhotoStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-demo-photos", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let repo = MockPhotoRepository()
        let weights = [86.4, 84.9, 83.1, 82.0, 80.6, 79.8, 78.9, 78.4]
        for (index, kg) in weights.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: -(7 - index) * 30 - 3, to: .now)!
            let photo = ProgressPhoto(id: UUID(), storagePath: "demo/\(index).jpg", takenAt: date, bodyWeightKg: kg)
            repo.photos.append(photo)
            repo.files[photo.storagePath] = placeholder(step: index).jpegData(compressionQuality: 0.8)
        }
        return PhotoStore(repository: repo, directory: directory)
    }

    /// A simple drawn figure that leans out as `step` grows.
    private static func placeholder(step: Int) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hex: 0x3A3631).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(hex: 0x4A423B).setFill()
            context.fill(CGRect(x: 0, y: 620, width: 600, height: 180))
            let skin = UIColor(hex: 0xC79B7A)
            skin.setFill()
            let waist = 190 - CGFloat(step) * 9
            UIBezierPath(ovalIn: CGRect(x: 255, y: 120, width: 90, height: 110)).fill()
            let torso = UIBezierPath()
            torso.move(to: CGPoint(x: 170, y: 270))
            torso.addLine(to: CGPoint(x: 430, y: 270))
            torso.addLine(to: CGPoint(x: 300 + waist / 2, y: 560))
            torso.addLine(to: CGPoint(x: 300 - waist / 2, y: 560))
            torso.close()
            torso.fill()
            UIColor(hex: 0x16171A).setFill()
            context.fill(CGRect(x: 300 - waist / 2 - 6, y: 555, width: waist + 12, height: 150))
            if step >= 4 {
                UIColor(hex: 0x9E7A5F).setStroke()
                let abs = UIBezierPath()
                for row in 0..<3 {
                    let y = CGFloat(400 + row * 45)
                    abs.move(to: CGPoint(x: 265, y: y)); abs.addLine(to: CGPoint(x: 335, y: y))
                }
                abs.move(to: CGPoint(x: 300, y: 380)); abs.addLine(to: CGPoint(x: 300, y: 530))
                abs.lineWidth = 4
                abs.stroke()
            }
        }
    }

    @MainActor
    static func prepareWorkout(in store: WorkoutStore) {
        if opensHold, let hang = store.library.exercise("Dead_Hang") {
            store.startWorkout(now: Date(timeIntervalSinceNow: -8 * 60))
            store.active?.addExercise(hang)
            store.active?.toggleHold(now: Date(timeIntervalSinceNow: -41))
            return
        }
        guard opensWorkout, let bench = store.library.exercise("Barbell_Bench_Press_-_Medium_Grip") else { return }
        store.startWorkout(now: Date(timeIntervalSinceNow: -19 * 60))
        store.active?.addExercise(bench)
        store.active?.completeFocusedSet(now: Date(timeIntervalSinceNow: -30))
        store.active?.adjustWeight(by: 2.5)
        if let incline = store.library.exercise("Incline_Dumbbell_Press") {
            store.active?.addExercise(incline)
        }
    }

    private static func sampleHistory() -> [WorkoutRow] {
        let plan: [(String, [(String, Double, Int)], Double)] = [
            ("Push day", [("Barbell_Bench_Press_-_Medium_Grip", 80, 8), ("Incline_Dumbbell_Press", 28, 10)], 3),
            ("Pull day", [("Barbell_Deadlift", 120, 5), ("Pullups", 0, 8)], 5),
            ("Legs", [("Barbell_Squat", 100, 6)], 7),
            ("Push day", [("Barbell_Bench_Press_-_Medium_Grip", 77.5, 8)], 10),
        ]
        var rows = plan.map { name, lifts, daysAgo -> WorkoutRow in
            let start = Date(timeIntervalSinceNow: -daysAgo * 86_400)
            var draft = WorkoutDraft(name: name, startedAt: start, endedAt: start.addingTimeInterval(55 * 60))
            draft.exercises = lifts.map { ref, weight, reps in
                DraftExercise(exerciseRef: ref, sets: (0..<3).map { _ in
                    DraftSet(weight: weight, reps: reps, completedAt: start)
                })
            }
            return WorkoutStore.localRow(draft)
        }
        // Benchmarks over the last six weeks
        let hangs = [(38, 42), (31, 51), (24, 55), (17, 63), (10, 60), (3, 72)]
        let planks = [(35, 75), (21, 95), (7, 110)]
        let pullups = [(33, 8), (19, 9), (5, 11)]
        let pushups = [(30, 28), (16, 32), (2, 35)]
        func benchmark(_ ref: String, _ name: String, daysAgo: Int, seconds: Int? = nil, reps: Int = 0) -> WorkoutRow {
            let start = Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400)
            var draft = WorkoutDraft(name: name, startedAt: start, endedAt: start.addingTimeInterval(120))
            draft.exercises = [DraftExercise(exerciseRef: ref, sets: [DraftSet(weight: 0, reps: reps, completedAt: start, durationSeconds: seconds)])]
            return WorkoutStore.localRow(draft)
        }
        rows += hangs.map { benchmark("Dead_Hang", "Dead Hang", daysAgo: $0.0, seconds: $0.1) }
        rows += planks.map { benchmark("Plank", "Plank", daysAgo: $0.0, seconds: $0.1) }
        rows += pullups.map { benchmark("Pullups", "Pullups", daysAgo: $0.0, reps: $0.1) }
        rows += pushups.map { benchmark("Pushups", "Pushups", daysAgo: $0.0, reps: $0.1) }
        return rows
    }
}
#endif
