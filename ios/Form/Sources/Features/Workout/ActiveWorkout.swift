import Foundation

/// The workout in progress. Every mutation is written to disk immediately.
@MainActor
@Observable
final class ActiveWorkout: Identifiable {
    nonisolated let id: UUID
    private(set) var draft: WorkoutDraft
    /// The set the big number and keys operate on.
    var focus: SetFocus?
    private(set) var restEndsAt: Date?
    private(set) var restTotal: TimeInterval = 0
    /// Increments when a rest finishes, so views can fire a haptic.
    private(set) var restFinishedCount = 0
    /// When the stopwatch for a timed hold started (dead hang, plank).
    private(set) var holdStartedAt: Date?

    struct SetFocus: Hashable {
        var exercise: Int
        var set: Int
    }

    private let store: DraftStore
    private let library: ExerciseLibrary
    private let lastSets: (String) -> [SetRow]?
    private var restTask: Task<Void, Never>?

    init(draft: WorkoutDraft, store: DraftStore, library: ExerciseLibrary = .shared,
         lastSets: @escaping (String) -> [SetRow]?) {
        self.id = draft.id
        self.draft = draft
        self.store = store
        self.library = library
        self.lastSets = lastSets
        self.focus = Self.firstOpenSet(in: draft)
    }

    // MARK: Reading

    var focusedExercise: DraftExercise? {
        focus.flatMap { draft.exercises.indices.contains($0.exercise) ? draft.exercises[$0.exercise] : nil }
    }

    var focusedSet: DraftSet? {
        guard let focus, let exercise = focusedExercise, exercise.sets.indices.contains(focus.set) else { return nil }
        return exercise.sets[focus.set]
    }

    func exercise(for ref: String) -> Exercise? { library.exercise(ref) }

    func previous(for ref: String) -> [SetRow]? { lastSets(ref) }

    var isFinishedLogging: Bool { !draft.exercises.isEmpty && focus == nil }

    func restRemaining(at date: Date) -> TimeInterval {
        guard let restEndsAt else { return 0 }
        return max(0, restEndsAt.timeIntervalSince(date))
    }

    // MARK: Exercises

    func addExercise(_ exercise: Exercise) {
        let previous = lastSets(exercise.id)
        let sets: [DraftSet]
        if let previous, !previous.isEmpty {
            sets = previous.map {
                DraftSet(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0, durationSeconds: $0.durationSeconds)
            }
        } else {
            sets = (0..<3).map { _ in
                switch exercise.metric {
                case .duration: DraftSet(weight: 0, reps: 0, durationSeconds: 30)
                case .bodyweightReps: DraftSet(weight: 0, reps: 8)
                case .weightReps: DraftSet(weight: exercise.kind.barWeight ?? 10, reps: 8)
                }
            }
        }
        draft.exercises.append(DraftExercise(exerciseRef: exercise.id, sets: sets))
        if focus == nil {
            focus = SetFocus(exercise: draft.exercises.count - 1, set: 0)
        }
        persist()
    }

    func removeExercise(at index: Int) {
        guard draft.exercises.indices.contains(index) else { return }
        draft.exercises.remove(at: index)
        focus = Self.firstOpenSet(in: draft)
        persist()
    }

    func addSet(toExercise index: Int) {
        guard draft.exercises.indices.contains(index) else { return }
        let template = draft.exercises[index].sets.last ?? DraftSet(weight: 0, reps: 8)
        draft.exercises[index].sets.append(DraftSet(kind: .normal, weight: template.weight, reps: template.reps,
                                                    durationSeconds: template.durationSeconds))
        if focus == nil {
            focus = SetFocus(exercise: index, set: draft.exercises[index].sets.count - 1)
        }
        persist()
    }

    func select(_ newFocus: SetFocus) {
        holdStartedAt = nil
        focus = newFocus
    }

    // MARK: Current set

    func adjustWeight(by delta: Double) {
        guard let focus, let exercise = focusedExercise, let set = focusedSet else { return }
        let kind = library.exercise(exercise.exerciseRef)?.kind ?? .other
        let newWeight = max(kind.minimumWeight, ((set.weight + delta) * 100).rounded() / 100)
        let oldWeight = set.weight
        // Carry the change to later open sets that had the same weight: the common "bump the whole lift" case.
        for index in draft.exercises[focus.exercise].sets.indices where index >= focus.set {
            let candidate = draft.exercises[focus.exercise].sets[index]
            if index == focus.set || (!candidate.isDone && candidate.weight == oldWeight) {
                draft.exercises[focus.exercise].sets[index].weight = newWeight
            }
        }
        persist()
    }

    func adjustReps(by delta: Int) {
        guard let focus, let set = focusedSet else { return }
        draft.exercises[focus.exercise].sets[focus.set].reps = max(0, set.reps + delta)
        persist()
    }

    func adjustDuration(by seconds: Int) {
        guard let focus, let set = focusedSet else { return }
        draft.exercises[focus.exercise].sets[focus.set].durationSeconds = max(0, (set.durationSeconds ?? 0) + seconds)
        persist()
    }

    /// Stopwatch for holds: first tap starts, second tap writes the elapsed seconds to the focused set.
    func toggleHold(now: Date = .now) {
        guard let focus, focusedSet != nil else { return }
        if let started = holdStartedAt {
            draft.exercises[focus.exercise].sets[focus.set].durationSeconds = max(0, Int(now.timeIntervalSince(started).rounded()))
            holdStartedAt = nil
            persist()
        } else {
            skipRest()
            holdStartedAt = now
        }
    }

    func holdElapsed(at date: Date) -> Int? {
        holdStartedAt.map { max(0, Int(date.timeIntervalSince($0))) }
    }

    func setKind(_ kind: SetKind) {
        guard let focus else { return }
        draft.exercises[focus.exercise].sets[focus.set].kind = kind
        persist()
    }

    /// Logs the focused set, starts rest, and moves focus to the next open set.
    func completeFocusedSet(now: Date = .now) {
        guard let focus, focusedSet != nil else { return }
        if holdStartedAt != nil { toggleHold(now: now) }
        draft.exercises[focus.exercise].sets[focus.set].completedAt = now
        let rest = TimeInterval(draft.exercises[focus.exercise].restSeconds)
        self.focus = Self.nextOpenSet(after: focus, in: draft)
        if self.focus != nil { startRest(seconds: rest, now: now) } else { skipRest() }
        persist()
    }

    func undoSet(_ target: SetFocus) {
        guard draft.exercises.indices.contains(target.exercise),
              draft.exercises[target.exercise].sets.indices.contains(target.set) else { return }
        draft.exercises[target.exercise].sets[target.set].completedAt = nil
        focus = target
        persist()
    }

    // MARK: Rest

    func startRest(seconds: TimeInterval, now: Date = .now) {
        restTotal = seconds
        restEndsAt = now.addingTimeInterval(seconds)
        scheduleRestEnd()
    }

    func adjustRest(by seconds: TimeInterval, now: Date = .now) {
        guard let restEndsAt else { return }
        let newEnd = max(now, restEndsAt.addingTimeInterval(seconds))
        restTotal = max(restTotal, newEnd.timeIntervalSince(now))
        self.restEndsAt = newEnd
        scheduleRestEnd()
    }

    func skipRest() {
        restTask?.cancel()
        restEndsAt = nil
    }

    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let restEndsAt else { return }
        restTask = Task { [weak self] in
            let wait = restEndsAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            self.restEndsAt = nil
            self.restFinishedCount += 1
        }
    }

    // MARK: Finishing

    func rename(_ name: String) {
        draft.name = name
        persist()
    }

    func markEnded(now: Date = .now) -> WorkoutDraft {
        skipRest()
        draft.endedAt = now
        persist()
        return draft
    }

    private func persist() {
        store.saveActive(draft)
    }

    // MARK: Focus helpers

    static func firstOpenSet(in draft: WorkoutDraft) -> SetFocus? {
        for (e, exercise) in draft.exercises.enumerated() {
            if let s = exercise.sets.firstIndex(where: { !$0.isDone }) {
                return SetFocus(exercise: e, set: s)
            }
        }
        return nil
    }

    static func nextOpenSet(after focus: SetFocus, in draft: WorkoutDraft) -> SetFocus? {
        let sets = draft.exercises[focus.exercise].sets
        if let s = sets.indices.first(where: { $0 > focus.set && !sets[$0].isDone }) {
            return SetFocus(exercise: focus.exercise, set: s)
        }
        if let s = sets.indices.first(where: { !sets[$0].isDone }) {
            return SetFocus(exercise: focus.exercise, set: s)
        }
        return firstOpenSet(in: draft)
    }
}
