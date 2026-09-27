import Foundation

/// The exercise catalogue: bundled exercises (read once) plus your own, which can change at runtime.
/// Lookups happen from any thread, so the custom list is lock-protected.
final class ExerciseLibrary: @unchecked Sendable {
    static let shared = ExerciseLibrary()

    let bundled: [Exercise]
    private let bundledByID: [String: Exercise]
    private let lock = NSLock()
    private var customList: [Exercise] = []
    private var customByID: [String: Exercise] = [:]

    init(bundle: Bundle = .main) {
        let list: [Exercise]
        if let url = bundle.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Exercise].self, from: data) {
            let ids = Set(decoded.map(\.id))
            list = decoded + Exercise.extras.filter { !ids.contains($0.id) }
        } else {
            list = Exercise.extras
        }
        bundled = list
        bundledByID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(exercises: [Exercise]) {
        bundled = exercises
        bundledByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Your exercises first, then the bundled catalogue.
    var all: [Exercise] { custom + bundled }

    var custom: [Exercise] { lock.withLock { customList } }

    func setCustom(_ exercises: [Exercise]) {
        lock.withLock {
            customList = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            customByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        }
    }

    func exercise(_ id: String) -> Exercise? {
        bundledByID[id] ?? lock.withLock { customByID[id] }
    }

    /// Unknown ids count as weight × reps.
    func metric(_ id: String) -> ExerciseMetric { exercise(id)?.metric ?? .weightReps }

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
