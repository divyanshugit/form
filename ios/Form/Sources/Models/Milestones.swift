import Foundation

/// Skill milestones from goals.md §4. Most tick themselves from logged sets, WHOOP runs and metrics;
/// any can be ticked by hand (a `milestone:<id>` metric).
struct Milestone: Identifiable, Hashable, Sendable {
    enum Track: String, CaseIterable, Identifiable, Sendable {
        case pullups, lsit, muscleup, running, deadlift, hyrox
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pullups: "Pull-ups"
            case .lsit: "L-sit"
            case .muscleup: "Muscle-up"
            case .running: "Running"
            case .deadlift: "Deadlift"
            case .hyrox: "HYROX"
            }
        }
        var symbol: String {
            switch self {
            case .pullups: "figure.climbing"
            case .lsit: "figure.core.training"
            case .muscleup: "figure.gymnastics"
            case .running: "figure.run"
            case .deadlift: "dumbbell.fill"
            case .hyrox: "flame.fill"
            }
        }
    }

    enum Rule: Hashable, Sendable {
        /// `sets` working sets of at least `reps` (and at least `addedKg`) in one session.
        case reps([String], reps: Int, sets: Int = 1, addedKg: Double = 0)
        case hold([String], seconds: Int)
        case lift([String], kg: Double)
        /// A lift of `multiple` × body weight on the day.
        case liftBodyweight([String], multiple: Double)
        /// A run (session name contains "run") of at least this distance.
        case runKm(Double)
        /// A session whose name contains this text.
        case session(String)
        /// Any metric of this kind.
        case metric(String)
        case manual
    }

    let id: String
    let track: Track
    let title: String
    let rule: Rule

    var manualKind: String { MetricKind.milestone(id) }
}

enum Milestones {
    static let pullupRefs = ["Pullups", "V-Bar_Pullup", "Wide-Grip_Rear_Pull-Up"]
    static let deadliftRefs = ["Barbell_Deadlift", "Sumo_Deadlift"]
    static let lsitRefs = ["L_Sit"]
    static let dipRefs = ["Dips_-_Triceps_Version"]

    static let all: [Milestone] = [
        Milestone(id: "pullup_neg_3x5", track: .pullups, title: "3×5 slow negatives",
                  rule: .reps(["Pullup_Negative"], reps: 5, sets: 3)),
        Milestone(id: "pullup_1", track: .pullups, title: "First strict pull-up", rule: .reps(pullupRefs, reps: 1)),
        Milestone(id: "pullup_5", track: .pullups, title: "5 strict pull-ups", rule: .reps(pullupRefs, reps: 5)),
        Milestone(id: "pullup_10", track: .pullups, title: "10 strict pull-ups", rule: .reps(pullupRefs, reps: 10)),
        Milestone(id: "pullup_15", track: .pullups, title: "15 strict pull-ups", rule: .reps(pullupRefs, reps: 15)),
        Milestone(id: "pullup_w10x5", track: .pullups, title: "Weighted pull-up +10 kg × 5",
                  rule: .reps(pullupRefs, reps: 5, addedKg: 10)),

        Milestone(id: "lsit_tuck_20", track: .lsit, title: "Tuck hold 20 s", rule: .hold(["Tuck_L_Sit"], seconds: 20)),
        Milestone(id: "lsit_one_leg_15", track: .lsit, title: "One leg out 15 s each", rule: .manual),
        Milestone(id: "lsit_5", track: .lsit, title: "Full L-sit 5 s", rule: .hold(lsitRefs, seconds: 5)),
        Milestone(id: "lsit_10", track: .lsit, title: "Full L-sit 10 s", rule: .hold(lsitRefs, seconds: 10)),
        Milestone(id: "lsit_20", track: .lsit, title: "Full L-sit 20 s", rule: .hold(lsitRefs, seconds: 20)),

        Milestone(id: "explosive_5", track: .muscleup, title: "Explosive pull-up to chest × 5",
                  rule: .reps(["Explosive_Pullup"], reps: 5)),
        Milestone(id: "dips_15", track: .muscleup, title: "15 straight-bar dips", rule: .reps(dipRefs, reps: 15)),
        Milestone(id: "muscleup_band_3", track: .muscleup, title: "Band-assisted muscle-up × 3", rule: .manual),
        Milestone(id: "muscleup_1", track: .muscleup, title: "First strict muscle-up", rule: .manual),
        Milestone(id: "muscleup_3", track: .muscleup, title: "3 muscle-ups in a row", rule: .manual),

        Milestone(id: "run_6k", track: .running, title: "6 km easy", rule: .runKm(6)),
        Milestone(id: "run_8k", track: .running, title: "8 km easy", rule: .runKm(8)),
        Milestone(id: "run_10k", track: .running, title: "10 km easy", rule: .runKm(10)),
        Milestone(id: "run_10k_race", track: .running, title: "10K race", rule: .manual),
        Milestone(id: "run_10k_pr", track: .running, title: "10K PR attempt", rule: .manual),

        Milestone(id: "dl_70", track: .deadlift, title: "70 kg (≈ body weight)", rule: .lift(deadliftRefs, kg: 70)),
        Milestone(id: "dl_100", track: .deadlift, title: "100 kg", rule: .lift(deadliftRefs, kg: 100)),
        Milestone(id: "dl_1_5bw", track: .deadlift, title: "1.5× body weight", rule: .liftBodyweight(deadliftRefs, multiple: 1.5)),
        Milestone(id: "dl_2bw", track: .deadlift, title: "2× body weight", rule: .liftBodyweight(deadliftRefs, multiple: 2)),

        Milestone(id: "hyrox_sim", track: .hyrox, title: "Full sim completed", rule: .session("hyrox")),
        Milestone(id: "hyrox_baseline", track: .hyrox, title: "Sim time baseline recorded",
                  rule: .metric(TestKind.hyroxTotal.metric)),
        Milestone(id: "hyrox_race", track: .hyrox, title: "First official race", rule: .manual),
        Milestone(id: "hyrox_race_pb", track: .hyrox, title: "Beat first race time", rule: .manual),
    ]

    static func milestone(_ id: String) -> Milestone? { all.first { $0.id == id } }

    struct Status: Identifiable, Sendable {
        let milestone: Milestone
        let achievedOn: Date?
        /// 0…1 toward the milestone from your best so far, when it can be measured.
        let progress: Double?
        /// "Best 3 reps", "Best 42 s".
        let best: String?
        var id: String { milestone.id }
        var isDone: Bool { achievedOn != nil }
    }

    /// Every milestone's status. Pure: history + metrics in, statuses out.
    static func evaluate(history: [WorkoutRow], metrics: [MetricRow],
                         baselineWeight: Double = Goals.baselineWeightKg) -> [Status] {
        let weights = MetricMath.series(metrics, kind: MetricKind.weight)
        func bodyweight(on date: Date) -> Double {
            weights.last { $0.recordedAt <= date }?.value ?? weights.first?.value ?? baselineWeight
        }
        let chronological = history.sorted { $0.startedAt < $1.startedAt }

        return all.map { milestone in
            let manual = metrics.filter { $0.kind == milestone.manualKind && $0.value > 0 }.map(\.recordedAt).min()
            let (auto, progress, best) = check(milestone.rule, in: chronological, metrics: metrics, bodyweight: bodyweight)
            let achieved = [manual, auto].compactMap { $0 }.min()
            return Status(milestone: milestone, achievedOn: achieved,
                          progress: achieved != nil ? 1 : progress, best: best)
        }
    }

    /// The next open milestone per track, in goals order.
    static func nextUp(_ statuses: [Status]) -> [Status] {
        Milestone.Track.allCases.compactMap { track in
            statuses.first { $0.milestone.track == track && !$0.isDone }
        }
    }

    /// The single most reachable open milestone: the one you're closest to.
    static func closest(_ statuses: [Status]) -> Status? {
        nextUp(statuses).filter { $0.milestone.rule != .manual }.max { ($0.progress ?? 0) < ($1.progress ?? 0) }
    }

    // MARK: Rules

    private static func workingSets(_ refs: [String], in workout: WorkoutRow) -> [SetRow] {
        workout.sortedExercises.filter { refs.contains($0.exerciseRef) }
            .flatMap(\.sortedSets).filter { $0.kind != .warmup }
    }

    private static func isRun(_ workout: WorkoutRow) -> Bool {
        workout.name.localizedCaseInsensitiveContains("run")
    }

    private static func check(_ rule: Milestone.Rule, in history: [WorkoutRow], metrics: [MetricRow],
                              bodyweight: (Date) -> Double) -> (Date?, Double?, String?) {
        switch rule {
        case let .reps(refs, reps, sets, addedKg):
            var bestReps = 0
            for workout in history {
                let qualifying = workingSets(refs, in: workout).filter { ($0.weightKg ?? 0) >= addedKg }
                bestReps = max(bestReps, qualifying.map { $0.reps ?? 0 }.max() ?? 0)
                if qualifying.filter({ ($0.reps ?? 0) >= reps }).count >= sets { return (workout.startedAt, 1, nil) }
            }
            return (nil, bestReps > 0 ? min(0.99, Double(bestReps) / Double(reps)) : nil,
                    bestReps > 0 ? "Best \(bestReps) rep\(bestReps == 1 ? "" : "s")" : nil)

        case let .hold(refs, seconds):
            var best = 0
            for workout in history {
                let hold = workingSets(refs, in: workout).map { $0.durationSeconds ?? 0 }.max() ?? 0
                best = max(best, hold)
                if hold >= seconds { return (workout.startedAt, 1, nil) }
            }
            return (nil, best > 0 ? min(0.99, Double(best) / Double(seconds)) : nil, best > 0 ? "Best \(best) s" : nil)

        case let .lift(refs, kg):
            var best = 0.0
            for workout in history {
                let top = workingSets(refs, in: workout).filter { ($0.reps ?? 0) >= 1 }.map { $0.weightKg ?? 0 }.max() ?? 0
                best = max(best, top)
                if top >= kg { return (workout.startedAt, 1, nil) }
            }
            return (nil, best > 0 ? min(0.99, best / kg) : nil, best > 0 ? "Best \(best.kg) kg" : nil)

        case let .liftBodyweight(refs, multiple):
            var bestRatio = 0.0
            for workout in history {
                let top = workingSets(refs, in: workout).filter { ($0.reps ?? 0) >= 1 }.map { $0.weightKg ?? 0 }.max() ?? 0
                let ratio = top / bodyweight(workout.startedAt)
                bestRatio = max(bestRatio, ratio)
                if top > 0, ratio >= multiple { return (workout.startedAt, 1, nil) }
            }
            return (nil, bestRatio > 0 ? min(0.99, bestRatio / multiple) : nil,
                    bestRatio > 0 ? String(format: "Best %.2f× BW", bestRatio) : nil)

        case let .runKm(km):
            let runMeters = Dictionary(MetricMath.series(metrics, kind: MetricKind.runMeters)
                .compactMap { m in m.workoutId.map { ($0, m.value) } }, uniquingKeysWith: max)
            var best = 0.0
            for workout in history where isRun(workout) {
                let meters = max(workout.distanceM ?? 0, runMeters[workout.id] ?? 0)
                best = max(best, meters)
                if meters >= km * 1000 * 0.97 { return (workout.startedAt, 1, nil) }
            }
            return (nil, best > 0 ? min(0.99, best / (km * 1000)) : nil,
                    best > 0 ? String(format: "Longest %.1f km", best / 1000) : nil)

        case let .session(text):
            let match = history.first { $0.name.localizedCaseInsensitiveContains(text) }
            return (match?.startedAt, nil, nil)

        case let .metric(kind):
            return (MetricMath.series(metrics, kind: kind).first?.recordedAt, nil, nil)

        case .manual:
            return (nil, nil, nil)
        }
    }
}
