import Foundation

/// Loads the bundled exercise list once and answers lookups and searches.
final class ExerciseLibrary: Sendable {
    static let shared = ExerciseLibrary()

    let all: [Exercise]
    private let byID: [String: Exercise]

    init(bundle: Bundle = .main) {
        let list: [Exercise]
        if let url = bundle.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
            list = decoded + Exercise.extras.filter { extra in !decoded.contains { $0.id == extra.id } }
        } else {
            list = Exercise.extras
        }
        all = list
        byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(exercises: [Exercise]) {
        all = exercises
        byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func exercise(_ id: String) -> Exercise? { byID[id] }

    /// Unknown ids (e.g. custom exercises) count as weight × reps.
    func metric(_ id: String) -> ExerciseMetric { byID[id]?.metric ?? .weightReps }

    /// Every distinct primary muscle, for filter chips.
    var muscles: [String] {
        Array(Set(all.compactMap { $0.primaryMuscles.first })).sorted()
    }

    func search(_ query: String, muscle: String? = nil) -> [Exercise] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return all.filter { exercise in
            if let muscle, exercise.primaryMuscles.first != muscle { return false }
            let haystack = exercise.name.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}
