import Foundation

enum HistoryFilter {
    /// A WHOOP-only walk nobody has defined: hidden from History by default.
    static func isWalk(_ workout: WorkoutRow) -> Bool {
        workout.isWhoopImport && workout.sortedExercises.isEmpty && workout.name == "Walking"
    }
}
