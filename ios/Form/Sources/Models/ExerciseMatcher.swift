import Foundation

/// Finds library exercises for free-typed or handwritten names ("12 KB Bent Over Row", "Heavy Goblet quat").
/// Expands gym shorthand, ignores filler words, tolerates one-letter misreads, and penalises equipment clashes.
struct ExerciseMatcher {
    struct Candidate: Equatable {
        let exercise: Exercise
        let score: Double

        static func == (a: Candidate, b: Candidate) -> Bool { a.exercise.id == b.exercise.id && a.score == b.score }
    }

    enum Confidence { case confident, check, none }

    static let confidentScore = 0.75
    static let suggestScore = 0.45

    private let entries: [(exercise: Exercise, tokens: [String])]
    /// Remembered picks: normalised name → exercise id. These always win.
    private let remembered: [String: String]

    init(exercises: [Exercise], remembered: [String: String] = [:]) {
        entries = exercises.map { ($0, Self.tokens($0.name)) }
        self.remembered = remembered
    }

    static func confidence(_ score: Double?) -> Confidence {
        guard let score else { return .none }
        if score >= confidentScore { return .confident }
        if score >= suggestScore { return .check }
        return .none
    }

    /// Best candidates, highest score first.
    func candidates(for name: String, limit: Int = 5) -> [Candidate] {
        let key = Self.key(name)
        var results: [Candidate] = []
        if let id = remembered[key], let entry = entries.first(where: { $0.exercise.id == id }) {
            results.append(Candidate(exercise: entry.exercise, score: 1))
        }
        let query = Self.tokens(name)
        guard !query.isEmpty else { return results }
        let scored = entries.compactMap { entry -> Candidate? in
            guard entry.exercise.id != results.first?.exercise.id else { return nil }
            let score = Self.score(query: query, candidate: entry.tokens)
            return score > 0 ? Candidate(exercise: entry.exercise, score: score) : nil
        }
        .sorted { a, b in
            a.score != b.score ? a.score > b.score : a.exercise.name.count < b.exercise.name.count
        }
        results.append(contentsOf: scored.prefix(limit))
        return Array(results.prefix(limit))
    }

    func best(for name: String) -> Candidate? {
        candidates(for: name, limit: 1).first.flatMap { $0.score >= Self.suggestScore ? $0 : nil }
    }

    // MARK: Normalising

    private static let abbreviations: [String: [String]] = [
        "db": ["dumbbell"], "dbs": ["dumbbell"], "kb": ["kettlebell"], "kbs": ["kettlebell"],
        "bb": ["barbell"], "sb": ["stability", "ball"], "bw": ["bodyweight"],
        "rdl": ["romanian", "deadlift"], "rdls": ["romanian", "deadlift"], "sldl": ["stiff", "legged", "deadlift"],
        "ohp": ["overhead", "press"], "hamst": ["hamstring"], "hams": ["hamstring"], "ham": ["hamstring"],
        "def": ["deficit"], "sl": ["single", "leg"], "alt": ["alternating"], "inc": ["incline"],
        "dec": ["decline"], "lat": ["lateral"], "lats": ["lateral"], "ext": ["extension"],
        "tri": ["triceps"], "tricep": ["triceps"], "bi": ["biceps"], "bicep": ["biceps"],
        "banded": ["band"], "bands": ["band"], "pullup": ["pull", "up"], "pullups": ["pull", "up"],
        "pushup": ["push", "up"], "pushups": ["push", "up"], "situp": ["sit", "up"], "situps": ["sit", "up"],
        "pushdown": ["push", "down"], "pushdowns": ["push", "down"], "pulldown": ["pull", "down"],
        "pulldowns": ["pull", "down"], "facepull": ["face", "pull"], "facepulls": ["face", "pull"],
    ]

    /// Phrases whose library wording differs from gym speak.
    private static let phrases: [([String], [String])] = [
        (["hamstring", "curl"], ["leg", "curl"]),
        (["military", "press"], ["shoulder", "press"]),
    ]

    private static let filler: Set<String> = [
        "heavy", "light", "slow", "tempo", "paused", "pause", "explosive", "the", "a", "an", "and", "with",
        "of", "to", "on", "each", "per", "x", "reps", "rep", "sets", "set", "max",
    ]

    private static let equipment: Set<String> = [
        "dumbbell", "barbell", "kettlebell", "cable", "machine", "band", "smith", "ez", "bodyweight",
    ]

    /// Lowercased, singular, abbreviations expanded, filler removed.
    static func tokens(_ name: String) -> [String] {
        let raw = name.lowercased()
            .replacingOccurrences(of: "push down", with: "pushdown")
            .replacingOccurrences(of: "pull down", with: "pulldown")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
        var words = raw.flatMap { abbreviations[$0] ?? [$0] }.map(stem).filter { !filler.contains($0) }
        for (from, to) in phrases {
            if let i = words.indices.first(where: { words[$0...].starts(with: from) }) {
                words.replaceSubrange(i..<i + from.count, with: to)
            }
        }
        return words
    }

    /// Key for remembering a pick; stable across small spacing/case differences.
    static func key(_ name: String) -> String { tokens(name).joined(separator: " ") }

    private static func stem(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"),
              !["triceps", "biceps", "abs"].contains(word) else { return word }
        return String(word.dropLast())
    }

    // MARK: Scoring

    private static func weight(_ token: String) -> Double { equipment.contains(token) ? 0.5 : 1 }

    private static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 4 else { return false }
        return editDistance(a, b, limit: 1) <= 1
    }

    /// Weighted Dice overlap, times 0.7 when the equipment named differs.
    static func score(query: [String], candidate: [String]) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        var used = Set<Int>()
        var matched = 0.0
        for q in query {
            if let i = candidate.indices.first(where: { !used.contains($0) && matches(q, candidate[$0]) }) {
                used.insert(i)
                matched += weight(q)
            }
        }
        guard matched > 0 else { return 0 }
        let total = query.map(weight).reduce(0, +) + candidate.map(weight).reduce(0, +)
        var score = 2 * matched / total
        let qEquip = Set(query).intersection(equipment), cEquip = Set(candidate).intersection(equipment)
        if !qEquip.isEmpty, !cEquip.isEmpty, qEquip.isDisjoint(with: cEquip) { score *= 0.7 }
        return score
    }

    private static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Remembers which exercise you picked for a board name, so the next scan gets it right.
enum BoardMemory {
    private static let key = "boardScan.picks"

    static func load(_ defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func remember(_ picks: [String: String], _ defaults: UserDefaults = .standard) {
        var all = load(defaults)
        all.merge(picks) { _, new in new }
        defaults.set(all, forKey: key)
    }
}
