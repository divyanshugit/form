import Foundation

/// Everything the Goals tab and Today derive from history + metrics, computed once per render.
@MainActor
struct ProgressSnapshot {
    let now: Date
    let phase: Goals.Phase
    let block: Goals.Block
    let milestones: [Milestones.Status]
    let criteria: [PhaseProgress.CriterionStatus]
    let since: Momentum.SinceDayOne
    let streak: Momentum.Streak
    let week: Momentum.Week
    let weights: [(date: Date, value: Double)]
    let waists: [(date: Date, value: Double)]
    let proteinStreak: Int

    init(store: WorkoutStore, metrics: MetricsStore, photos: PhotoStore, now: Date = .now) {
        self.now = now
        phase = Goals.phase(on: now)
        block = Goals.block(on: now)
        milestones = Milestones.evaluate(history: store.history, metrics: metrics.rows)
        criteria = PhaseProgress.evaluate(phase, milestones: milestones, history: store.history, metrics: metrics.rows)
        since = Momentum.sinceDayOne(history: store.history, now: now)
        streak = Momentum.weeklyStreak(history: store.history, now: now)
        week = Momentum.week(containing: now, history: store.history)
        weights = Self.weights(metrics: metrics.rows, photos: photos.photos)
        waists = metrics.series(MetricKind.waist).map { ($0.recordedAt, $0.value) }
        let proteinDays = Set(metrics.series(MetricKind.proteinOK).filter { $0.value > 0 }
            .map { Calendar.current.startOfDay(for: $0.recordedAt) })
        proteinStreak = Momentum.dailyStreak(days: proteinDays, now: now)
    }

    /// Morning weigh-ins plus weights typed on progress photos, oldest first.
    static func weights(metrics: [MetricRow], photos: [ProgressPhoto]) -> [(date: Date, value: Double)] {
        let logged = MetricMath.series(metrics, kind: MetricKind.weight).map { ($0.recordedAt, $0.value) }
        let fromPhotos = photos.compactMap { photo in photo.bodyWeightKg.map { (photo.takenAt, $0) } }
        return (logged + fromPhotos).sorted { $0.0 < $1.0 }.map { (date: $0.0, value: $0.1) }
    }

    var dayNumber: Int { Self.dayNumber(now) }

    static func dayNumber(_ date: Date) -> Int {
        (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Goals.dayZero),
                                         to: Calendar.current.startOfDay(for: date)).day ?? 0) + 1
    }

    var weightChange: Double? {
        guard let first = weights.first, let last = weights.last, weights.count > 1 else { return nil }
        let recent = MetricMath.average(weights, endingAt: now) ?? last.value
        return recent - first.value
    }

    var achievedCount: Int { milestones.filter(\.isDone).count }

    var closest: Milestones.Status? { Milestones.closest(milestones) }

    var weeksLeftInPhase: Int { Goals.weeks(from: now, to: phase.end) }
}
