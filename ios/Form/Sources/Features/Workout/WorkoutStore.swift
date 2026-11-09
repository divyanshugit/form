import Foundation

/// App-wide workout state: the active workout, history, and offline-first sync.
@MainActor
@Observable
final class WorkoutStore {
    private(set) var active: ActiveWorkout?
    private(set) var history: [WorkoutRow] = [] {
        didSet {
            bestsCache = nil
            trendCache = [:]
        }
    }
    @ObservationIgnored private var bestsCache: [String: Records.Best]?
    @ObservationIgnored private var trendCache: [String: [(date: Date, value: Double)]] = [:]
    @ObservationIgnored private var isSyncing = false
    private(set) var pendingCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    private let repository: WorkoutRepository
    private let store: DraftStore
    let library: ExerciseLibrary

    init(repository: WorkoutRepository = SupabaseWorkoutRepository(),
         store: DraftStore = DraftStore(),
         library: ExerciseLibrary = .shared) {
        self.repository = repository
        self.store = store
        self.library = library
        pendingCount = store.pending().count
        if let draft = store.loadActive() {
            active = makeActive(draft)
        }
    }

    // MARK: Active workout

    func startWorkout(now: Date = .now) {
        guard active == nil else { return }
        let draft = WorkoutDraft(name: Self.defaultName(for: now), startedAt: now)
        store.saveActive(draft)
        active = makeActive(draft)
    }

    /// Starts a session from a program template, each exercise loaded with its double-progression target.
    func startWorkout(template: Program.Template, now: Date = .now) {
        guard active == nil else { return }
        startWorkout(now: now)
        guard let active else { return }
        active.rename(template.name)
        for slot in template.slots {
            guard let exercise = library.exercise(slot.ref) else { continue }
            let last = Records.lastSets(for: slot.ref, in: history)
            let target = Program.target(for: slot, metric: exercise.metric, kind: exercise.kind, last: last)
            var note = slot.seconds.map { "Target \(slot.sets) × \($0) s" }
                ?? "Target \(slot.sets) × \(slot.repMin == slot.repMax ? "\(slot.repMax)" : "\(slot.repMin)–\(slot.repMax)")"
            if let extra = slot.note { note += " · \(extra)" }
            if let reason = target.reason { note += " · \(reason)" }
            active.addPlanned(exercise, sets: slot.sets, target: target, note: note)
        }
    }

    func discardActive() {
        store.clearActive()
        active = nil
    }

    /// Ends the workout, queues it for upload, and syncs. The workout is safe on disk before any network call.
    @discardableResult
    func finishActive(now: Date = .now) async -> WorkoutDraft? {
        guard let active else { return nil }
        let draft = active.markEnded(now: now)
        guard !draft.completedSets.isEmpty else {
            discardActive()
            return nil
        }
        store.setPending(store.pending().filter { $0.id != draft.id } + [draft])
        store.clearActive()
        self.active = nil
        insertLocally(draft)
        await syncPending()
        return draft
    }

    /// Saves a session logged after the fact (quick log). Same offline-first path as a finished workout.
    func logManual(_ draft: WorkoutDraft) async {
        guard draft.exercises.contains(where: { $0.sets.contains(where: \.isDone) }) else { return }
        store.setPending(store.pending().filter { $0.id != draft.id } + [draft])
        insertLocally(draft)
        await syncPending()
    }

    // MARK: History & sync

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await syncPending()
        do {
            let remote = try await repository.recentWorkouts(limit: 2000)
            let pendingIDs = Set(store.pending().map(\.id))
            // Keep not-yet-uploaded workouts visible alongside the server copy.
            history = (remote.filter { !pendingIDs.contains($0.id) } + store.pending().map(Self.localRow))
                .sorted { $0.startedAt > $1.startedAt }
            errorMessage = nil
            await nameImportedSessions()
        } catch {
            errorMessage = "Couldn't reach the server. Your workouts are saved on this phone."
        }
    }

    /// Uploads queued workouts. Single-flight; a draft leaves the queue only once it's saved,
    /// so a failure in one pass can never drop a workout another caller queued.
    func syncPending() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            pendingCount = store.pending().count
        }
        var attempted = Set<UUID>()
        while let draft = store.pending().first(where: { !attempted.contains($0.id) }) {
            attempted.insert(draft.id)
            do {
                try await repository.save(draft)
                store.setPending(store.pending().filter { $0.id != draft.id })
            } catch {
                continue
            }
        }
    }

    func delete(_ workout: WorkoutRow) async {
        history.removeAll { $0.id == workout.id }
        store.setPending(store.pending().filter { $0.id != workout.id })
        try? await repository.delete(workoutID: workout.id)
    }

    /// Saves an edited session, keeping its WHOOP data. Updates the list immediately.
    func update(_ draft: WorkoutDraft, keeping original: WorkoutRow) async {
        var row = Self.localRow(draft)
        row.whoopWorkoutId = original.whoopWorkoutId
        row.strain = original.strain
        row.avgHr = original.avgHr
        row.maxHr = original.maxHr
        row.kcal = original.kcal
        row.zoneMs = original.zoneMs
        row.distanceM = original.distanceM
        if let index = history.firstIndex(where: { $0.id == draft.id }) { history[index] = row }
        do {
            try await repository.replace(draft)
        } catch {
            errorMessage = "Couldn't save your changes. Check your connection and try again."
        }
    }

    // MARK: WHOOP

    /// Renames WHOOP imports that are really something specific: Saturday-morning "Functional Fitness"
    /// is the team HYROX sim. Runs once per session, since renamed rows no longer match.
    func nameImportedSessions() async {
        let rename = history.filter {
            $0.isWhoopImport && $0.sortedExercises.isEmpty
                && SessionNaming.isHyroxSim(sportName: $0.name, start: $0.startedAt)
        }
        for row in rename {
            var draft = WorkoutDraft(id: row.id, name: SessionNaming.hyroxSim, startedAt: row.startedAt, endedAt: row.endedAt)
            draft.notes = row.notes
            await update(draft, keeping: row)
        }
    }

    /// Applies a WHOOP sync plan. Returns a description of the first failure, if any.
    @discardableResult
    func apply(_ plan: WhoopMatching.Plan) async -> String? {
        var failure: String?
        for (workoutID, whoop) in plan.attach + plan.update {
            guard let index = history.firstIndex(where: { $0.id == workoutID }) else { continue }
            let isImport = history[index].isWhoopImport
            do { try await repository.attachWhoop(whoop, to: workoutID, includingTimes: isImport) } catch {
                failure = failure ?? error.localizedDescription
            }
            history[index].take(whoop)
        }
        if !plan.update.isEmpty {
            history.sort { $0.startedAt > $1.startedAt }
        }
        for id in plan.removeImported {
            try? await repository.delete(workoutID: id)
            history.removeAll { $0.id == id }
        }
        let imported = plan.imports.compactMap(WorkoutRow.imported(from:))
        do {
            try await repository.upsertImported(imported)
            let ids = Set(imported.map(\.id))
            history = (history.filter { !ids.contains($0.id) } + imported).sorted { $0.startedAt > $1.startedAt }
        } catch {
            failure = failure ?? error.localizedDescription
        }
        return failure
    }

    // MARK: Derived

    /// Best efforts per exercise across all history, cached until history changes.
    var bests: [String: Records.Best] {
        if let bestsCache { return bestsCache }
        let computed = Records.bests(in: history)
        bestsCache = computed
        return computed
    }

    /// Per-session best for one exercise, oldest first. Cached until history changes.
    func trend(for exerciseRef: String, metric: ExerciseMetric) -> [(date: Date, value: Double)] {
        let key = exerciseRef + "|" + metric.rawValue
        if let cached = trendCache[key] { return cached }
        let computed = Records.trend(for: exerciseRef, metric: metric, in: history)
        trendCache[key] = computed
        return computed
    }

    func records(for draft: WorkoutDraft) -> [PersonalRecord] {
        Records.newRecords(in: draft, history: history)
    }

    /// Days (start of day) with at least one workout, for the year grid and streaks.
    var trainedDays: Set<Date> {
        Set(history.map { Calendar.current.startOfDay(for: $0.startedAt) })
    }

    // MARK: Helpers

    private func makeActive(_ draft: WorkoutDraft) -> ActiveWorkout {
        ActiveWorkout(draft: draft, store: store, library: library) { [weak self] ref in
            guard let self else { return nil }
            return Records.lastSets(for: ref, in: self.history)
        }
    }

    private func insertLocally(_ draft: WorkoutDraft) {
        history.removeAll { $0.id == draft.id }
        history.append(Self.localRow(draft))
        history.sort { $0.startedAt > $1.startedAt }
    }

    nonisolated static func localRow(_ draft: WorkoutDraft) -> WorkoutRow {
        let rows = draft.rows()
        var workout = rows.workout
        workout.workoutExercises = rows.exercises.map { exercise in
            var e = exercise
            e.sets = rows.sets.filter { $0.workoutExerciseId == exercise.id }
            return e
        }
        return workout
    }

    nonisolated static func defaultName(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning session"
        case 12..<17: return "Afternoon session"
        default: return "Evening session"
        }
    }
}
