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
    /// Your own words, for exercises you create.
    var about: String? = nil
    /// Set on your own exercises; bundled ones derive their metric.
    var metricOverride: ExerciseMetric? = nil

    var kind: EquipmentKind { EquipmentKind(equipment) }

    var isCustom: Bool { id.hasPrefix(Exercise.customPrefix) }
    static let customPrefix = "custom:"

    /// What a set of this exercise records.
    var metric: ExerciseMetric {
        if let metricOverride { return metricOverride }
        if ExerciseMetric.timedIDs.contains(id) { return .duration }
        return kind == .bodyweight ? .bodyweightReps : .weightReps
    }

    /// Two or three lines on what the exercise is: yours if you wrote one, otherwise built from the data.
    var summary: String {
        if let about, !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return about }
        var lines: [String] = []

        let muscle = primaryMuscles.first ?? "full-body"
        let noun = metric == .duration ? "hold" : "exercise"
        let style: String? = switch mechanic {
        case "compound": "compound"
        case "isolation": "isolation"
        default: nil
        }
        let words = [style, muscle, noun].compactMap { $0 }.joined(separator: " ")
        let article = "aeiou".contains(words.first ?? "x") ? "An" : "A"
        let tool: String = switch equipment {
        case "barbell": " with a barbell"
        case "dumbbell": " with dumbbells"
        case "kettlebell": " with a kettlebell"
        case "ez bar": " with an EZ bar"
        case "cable": " on a cable stack"
        case "machine": " on a machine"
        case "bands": " with a resistance band"
        case "bodyweight": " using your bodyweight"
        default: ""
        }
        lines.append("\(article) \(words)\(tool).")

        if !secondaryMuscles.isEmpty {
            let list = ListFormatter.localizedString(byJoining: secondaryMuscles)
            lines.append("Also works your \(list).")
        }

        if let first = instructions.first {
            let sentence = first.split(separator: ".", maxSplits: 1).first.map(String.init) ?? first
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(trimmed.count > 140 ? String(trimmed.prefix(137)) + "…" : trimmed + ".") }
        }
        return lines.joined(separator: " ")
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
        "Plank", "Dead_Hang", "L_Sit", "Wall_Sit", "Hollow_Body_Hold", "Side_Plank", "Tuck_L_Sit",
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
        Exercise(id: "Tuck_L_Sit", name: "Tuck L-Sit", equipment: "bodyweight",
                 primaryMuscles: ["abdominals"], secondaryMuscles: ["triceps"], mechanic: "isolation",
                 instructions: ["Support yourself on parallettes, dip bars or the floor.", "Pull your knees to your chest, feet off the ground, and hold."],
                 images: []),
        Exercise(id: "Pullup_Negative", name: "Pull-up Negative", equipment: "bodyweight",
                 primaryMuscles: ["lats"], secondaryMuscles: ["biceps", "middle back"], mechanic: "compound",
                 instructions: ["Jump or step to the top of a pull-up, chin over the bar.", "Lower yourself slowly, 3 to 5 seconds, to a dead hang."],
                 images: []),
        Exercise(id: "Pike_Pushup", name: "Pike Push-up", equipment: "bodyweight",
                 primaryMuscles: ["shoulders"], secondaryMuscles: ["triceps"], mechanic: "compound",
                 instructions: ["Hips high, body in an upside-down V, hands shoulder-width.", "Lower the top of your head toward the floor, then press back up."],
                 images: []),
        Exercise(id: "Explosive_Pullup", name: "Explosive Pull-up", equipment: "bodyweight",
                 primaryMuscles: ["lats"], secondaryMuscles: ["biceps"], mechanic: "compound",
                 instructions: ["Pull as fast as you can, aiming the bar at your lower chest.", "Lower under control. Muscle-up groundwork."],
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
