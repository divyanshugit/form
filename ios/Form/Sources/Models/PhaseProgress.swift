import Foundation

/// Where I stand against the current phase: exit criteria met, baseline vs now. Pure.
enum PhaseProgress {
    static let mainLifts = [
        "Barbell_Deadlift", "Barbell_Squat", "Barbell_Bench_Press_-_Medium_Grip",
        "Standing_Military_Press", "Incline_Dumbbell_Press", "Bent_Over_Two-Dumbbell_Row", "Romanian_Deadlift",
    ]

    struct CriterionStatus: Identifiable, Sendable {
        let criterion: Goals.Criterion
        let met: Bool
        let detail: String?
        var id: String { criterion.id }
    }

    static func evaluate(_ phase: Goals.Phase, milestones: [Milestones.Status], history: [WorkoutRow],
                         metrics: [MetricRow], cutoff: Date = Goals.baselineCutoff) -> [CriterionStatus] {
        phase.exit.map { criterion in
            let manual = metrics.contains { $0.kind == MetricKind.milestone(criterion.id) && $0.value > 0 }
            switch criterion.check {
            case .milestone(let id):
                let status = milestones.first { $0.id == id }
                return CriterionStatus(criterion: criterion, met: manual || status?.isDone == true, detail: status?.best)
            case .liftsUp:
                let lifts = liftsVsBaseline(history: history, cutoff: cutoff)
                let up = lifts.filter { $0.now > $0.baseline }.count
                return CriterionStatus(criterion: criterion, met: manual || (!lifts.isEmpty && up == lifts.count),
                                       detail: lifts.isEmpty ? "Baseline set on test day" : "\(up) of \(lifts.count) up")
            case .waistNotUp:
                let waist = MetricMath.series(metrics, kind: MetricKind.waist)
                let baseline = waist.last { $0.recordedAt <= cutoff } ?? waist.first
                guard let baseline, let latest = waist.last, latest.id != baseline.id else {
                    return CriterionStatus(criterion: criterion, met: manual, detail: waist.isEmpty ? "Measure your waist" : nil)
                }
                let change = latest.value - baseline.value
                return CriterionStatus(criterion: criterion, met: manual || change <= 0,
                                       detail: String(format: "%+.1f cm vs baseline", change))
            case .manual:
                return CriterionStatus(criterion: criterion, met: manual, detail: nil)
            }
        }
    }

    struct LiftChange: Identifiable, Sendable {
        let ref: String
        let baseline: Double
        let now: Double
        var id: String { ref }
    }

    /// Estimated 1RM per main lift: best up to the cutoff vs best overall. Lifts with no logged weight
    /// before the cutoff have no baseline yet.
    static func liftsVsBaseline(history: [WorkoutRow], cutoff: Date, refs: [String] = mainLifts) -> [LiftChange] {
        refs.compactMap { ref in
            func best(_ rows: [WorkoutRow]) -> Double {
                rows.flatMap { $0.sortedExercises.filter { $0.exerciseRef == ref } }
                    .flatMap(\.sortedSets).filter { $0.kind != .warmup && ($0.weightKg ?? 0) > 0 }
                    .map { PlateMath.estimatedOneRepMax(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }.max() ?? 0
            }
            let baseline = best(history.filter { $0.startedAt <= cutoff })
            guard baseline > 0 else { return nil }
            return LiftChange(ref: ref, baseline: baseline, now: max(baseline, best(history)))
        }
    }

    /// Phase 1 baseline for a test: the last value logged up to the cutoff (or the first ever).
    static func baseline(_ test: TestKind, metrics: [MetricRow], cutoff: Date = Goals.baselineCutoff) -> MetricRow? {
        let series = MetricMath.series(metrics, kind: test.metric)
        return series.last { $0.recordedAt <= cutoff } ?? series.first
    }

    /// Fraction of the phase elapsed.
    static func elapsed(_ phase: Goals.Phase, now: Date) -> Double {
        let total = phase.end.timeIntervalSince(phase.start)
        return min(1, max(0, now.timeIntervalSince(phase.start) / total))
    }
}
