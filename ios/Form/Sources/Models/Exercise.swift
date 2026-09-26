import Foundation

/// One exercise from the bundled library (free-exercise-db, public domain).
struct Exercise: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let mechanic: String?
    let instructions: [String]
    let images: [String]

    var kind: EquipmentKind { EquipmentKind(equipment) }

    /// What a set of this exercise records.
    var metric: ExerciseMetric {
        if ExerciseMetric.timedIDs.contains(id) { return .duration }
        return kind == .bodyweight ? .bodyweightReps : .weightReps
    }

    var primaryMuscle: String { primaryMuscles.first?.capitalized ?? "" }

    /// Images are served from the dataset's GitHub repo via jsDelivr and cached by URLCache.
    var imageURL: URL? {
        images.first.flatMap {
            URL(string: "https://cdn.jsdelivr.net/gh/yuhonas/free-exercise-db@main/exercises/\($0)")
        }
    }
}

/// What gets logged per set.
enum ExerciseMetric: String, Codable, Sendable {
    /// Weight × reps (bench, squat, curls).
    case weightReps
    /// Reps are the score, optional added weight (pull-ups, push-ups, dips).
    case bodyweightReps
    /// A hold measured in seconds (dead hang, plank, L-sit).
    case duration

    static let timedIDs: Set<String> = [
        "Plank", "Dead_Hang", "L_Sit", "Wall_Sit", "Hollow_Body_Hold", "Side_Plank",
    ]
}

extension Exercise {
    /// Holds and benchmarks missing from free-exercise-db.
    static let extras: [Exercise] = [
        Exercise(id: "Dead_Hang", name: "Dead Hang", equipment: "bodyweight",
                 primaryMuscles: ["forearms"], secondaryMuscles: ["lats", "shoulders"], mechanic: "isolation",
                 instructions: ["Hang from a pull-up bar with straight arms, shoulders active.", "Hold as long as you can with good form."],
                 images: []),
        Exercise(id: "L_Sit", name: "L-Sit", equipment: "bodyweight",
                 primaryMuscles: ["abdominals"], secondaryMuscles: ["quadriceps", "triceps"], mechanic: "isolation",
                 instructions: ["Support yourself on parallettes or a dip bar.", "Lift straight legs to horizontal and hold."],
                 images: []),
        Exercise(id: "Wall_Sit", name: "Wall Sit", equipment: "bodyweight",
                 primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], mechanic: "isolation",
                 instructions: ["Back flat against a wall, thighs parallel to the floor.", "Hold."],
                 images: []),
        Exercise(id: "Hollow_Body_Hold", name: "Hollow Body Hold", equipment: "bodyweight",
                 primaryMuscles: ["abdominals"], secondaryMuscles: [], mechanic: "isolation",
                 instructions: ["Lie on your back, lower back pressed down, arms and legs lifted.", "Hold."],
                 images: []),
        Exercise(id: "Side_Plank", name: "Side Plank", equipment: "bodyweight",
                 primaryMuscles: ["abdominals"], secondaryMuscles: ["glutes"], mechanic: "isolation",
                 instructions: ["Support yourself on one forearm, body in a straight line.", "Hold, then switch sides."],
                 images: []),
    ]
}

/// How weight is loaded, which drives the weight control and step sizes.
enum EquipmentKind: String, Codable, Sendable {
    case barbell, ezBar, dumbbell, machine, bodyweight, other

    init(_ equipment: String?) {
        switch equipment {
        case "barbell": self = .barbell
        case "ez bar": self = .ezBar
        case "dumbbell", "kettlebell": self = .dumbbell
        case "cable", "machine": self = .machine
        case "bodyweight": self = .bodyweight
        default: self = .other
        }
    }

    var barWeight: Double? {
        switch self {
        case .barbell: 20
        case .ezBar: 10
        default: nil
        }
    }

    /// Small and large step for the − / + keys.
    var steps: (small: Double, large: Double) {
        switch self {
        case .barbell, .ezBar: (2.5, 5)
        case .dumbbell: (2, 4)
        case .machine, .other: (5, 10)
        case .bodyweight: (2.5, 5)
        }
    }

    var minimumWeight: Double { barWeight ?? 0 }
}
