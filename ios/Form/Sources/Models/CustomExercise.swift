import Foundation

/// An exercise you created, as stored in `form.custom_exercises`.
struct CustomExerciseRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var equipment: String?
    var primaryMuscle: String?
    var secondaryMuscles: [String] = []
    var metric: ExerciseMetric
    var description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, equipment, metric, description
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
    }

    /// The exercise as the rest of the app sees it; its id is `custom:<uuid>`.
    var exercise: Exercise {
        Exercise(id: Exercise.customPrefix + id.uuidString.lowercased(), name: name, equipment: equipment,
                 primaryMuscles: primaryMuscle.map { [$0] } ?? [], secondaryMuscles: secondaryMuscles,
                 mechanic: nil, instructions: [], images: [], about: description, metricOverride: metric)
    }

    static let equipmentChoices = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "kettlebell", "ez bar", "bands", "other"]
}
