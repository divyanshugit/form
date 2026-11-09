import Foundation

/// goals.md §6 decision rules, readiness and deload, as pure functions over the data.
enum Rules {
    struct Suggestion: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable { case keepGoing, review, dropCalories, addCalories, carbsForHardDays, measure, deload }
        let kind: Kind
        let title: String
        let detail: String
        var id: String { kind.rawValue }
    }

    struct Input: Sendable {
        var now: Date
        var history: [WorkoutRow]
        var weights: [(date: Date, value: Double)]
        var waists: [(date: Date, value: Double)]
        /// WHOOP recovery by day.
        var recoveries: [(date: Date, value: Double)] = []
        var lastDeload: Date? = nil
        var metric: Records.MetricLookup = Records.defaultMetric
    }

    struct Trends: Sendable {
        /// kg per 30 days, from 7-day averages ~4 weeks apart.
        var weightPerMonth: Double?
        /// cm change across the last 4 weeks of waist entries.
        var waistChange: Double?
        var prsLast14: Int
        var prsLast21: Int
        var loadedSessionsLast21: Int
        var strengthUp: Bool { prsLast14 > 0 }
        var strengthFlat: Bool { prsLast21 == 0 && loadedSessionsLast21 >= 6 }
        var weightFlat: Bool { weightPerMonth.map { abs($0) < 0.3 } ?? false }
    }

    static func trends(_ input: Input) -> Trends {
        let day = 86_400.0
        var perMonth: Double?
        if let now = MetricMath.average(input.weights, endingAt: input.now),
           let then = MetricMath.average(input.weights, endingAt: input.now.addingTimeInterval(-28 * day)) {
            perMonth = (now - then) * 30 / 28
        }
        let recentWaist = input.waists.filter { $0.date > input.now.addingTimeInterval(-35 * day) }.sorted { $0.date < $1.date }
        let waistChange: Double? = recentWaist.count >= 2 ? recentWaist.last!.value - recentWaist.first!.value : nil

        let prs = Momentum.prEvents(history: Momentum.training(input.history), metric: input.metric)
        let from14 = input.now.addingTimeInterval(-14 * day), from21 = input.now.addingTimeInterval(-21 * day)
        let loaded = Momentum.training(input.history).filter { workout in
            workout.startedAt > from21 && workout.sortedExercises.contains { exercise in
                exercise.sortedSets.contains { ($0.weightKg ?? 0) > 0 }
            }
        }
        return Trends(weightPerMonth: perMonth, waistChange: waistChange,
                      prsLast14: prs.filter { $0.date > from14 }.count,
                      prsLast21: prs.filter { $0.date > from21 }.count,
                      loadedSessionsLast21: loaded.count)
    }

    /// The week's suggestions, most important first.
    static func weeklyReview(_ input: Input) -> [Suggestion] {
        let t = trends(input)
        var out: [Suggestion] = []
        let day = 86_400.0

        if (t.weightPerMonth ?? 0) > 1 || (t.waistChange ?? 0) >= 1 {
            let why = (t.waistChange ?? 0) >= 1
                ? String(format: "Waist up %.1f cm in 4 weeks.", t.waistChange!)
                : String(format: "Weight up %.1f kg a month on the 7-day average.", t.weightPerMonth!)
            out.append(Suggestion(kind: .dropCalories, title: "Drop 150–200 kcal a day", detail: why + " Faster than lean gain."))
        } else if t.weightFlat && t.strengthFlat {
            out.append(Suggestion(kind: .addCalories, title: "Add ~200 kcal, mostly carbs",
                                  detail: "Weight flat for a month and no PRs in 3 weeks. Fuel the training."))
        }
        if t.strengthFlat {
            out.append(Suggestion(kind: .review, title: "Strength flat for 3 weeks",
                                  detail: "Check effort (1–2 reps short of failure), food and sleep before changing the program."))
        }
        if drainingHardDays(input) {
            out.append(Suggestion(kind: .carbsForHardDays, title: "More carbs on Friday and Saturday",
                                  detail: "Recovery dipped into the red after your last run or HYROX days."))
        }
        if let deload = deload(input, trends: t) { out.append(deload) }
        if t.strengthUp && (t.waistChange ?? 0) <= 0.5 && !out.contains(where: { $0.kind == .dropCalories }) {
            out.insert(Suggestion(kind: .keepGoing, title: "Keep going",
                                  detail: "\(t.prsLast14) PR\(t.prsLast14 == 1 ? "" : "s") in 2 weeks and waist steady. The plan is working."), at: 0)
        }
        if !input.weights.contains(where: { $0.date > input.now.addingTimeInterval(-7 * day) }) {
            out.append(Suggestion(kind: .measure, title: "Weigh in this week",
                                  detail: "Morning, after the bathroom, before food. The 7-day average drives the rules."))
        } else if !input.waists.contains(where: { $0.date > input.now.addingTimeInterval(-10 * day) }) {
            out.append(Suggestion(kind: .measure, title: "Measure your waist",
                                  detail: "At the navel, morning, relaxed. Weekly is enough."))
        }
        return out
    }

    /// Two or more red recoveries (< 34) the morning after a run or HYROX session in the last 3 weeks.
    static func drainingHardDays(_ input: Input, calendar: Calendar = .current) -> Bool {
        let from = input.now.addingTimeInterval(-21 * 86_400)
        let hard = Momentum.training(input.history).filter {
            $0.startedAt > from && ($0.name.localizedCaseInsensitiveContains("run") || $0.name.localizedCaseInsensitiveContains("hyrox"))
        }
        let red = hard.filter { session in
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: session.startedAt))!
            return input.recoveries.contains { calendar.isDate($0.date, inSameDayAs: next) && $0.value < 34 }
        }
        return red.count >= 2
    }

    /// A deload every 6–8 weeks of training, or sooner when strength has stalled for 3 weeks after 5+.
    static func deload(_ input: Input, trends t: Trends? = nil) -> Suggestion? {
        let t = t ?? trends(input)
        let sessions = Momentum.training(input.history)
        guard let first = sessions.map(\.startedAt).min() else { return nil }
        let since = max(input.lastDeload ?? first, first)
        let weeks = Goals.weeks(from: since, to: input.now)
        if weeks >= 7 {
            return Suggestion(kind: .deload, title: "Deload week",
                              detail: "\(weeks) weeks since the last easy week. Same lifts, ~60% of the weight, half the sets.")
        }
        if weeks >= 5 && t.strengthFlat {
            return Suggestion(kind: .deload, title: "Deload week",
                              detail: "Lifts have stalled after \(weeks) weeks. A lighter week usually unlocks them.")
        }
        return nil
    }

    // MARK: Readiness

    enum Readiness: String, Sendable {
        case push, steady, ease

        var title: String {
            switch self {
            case .push: "Push today"
            case .steady: "Train as planned"
            case .ease: "Ease off"
            }
        }

        var detail: String {
            switch self {
            case .push: "Recovered and fresh. Go for the top of the rep range."
            case .steady: "Normal session. Stop 2 reps short of failure."
            case .ease: "Lighter weights, fewer sets, or a walk. It still counts."
            }
        }
    }

    /// WHOOP recovery + soreness (1–5) + yesterday's strain.
    static func readiness(recovery: Double?, soreness: Int?, yesterdayStrain: Double?) -> Readiness {
        var score = recovery ?? 60
        switch soreness ?? 2 {
        case 5: score -= 35
        case 4: score -= 20
        case 3: score -= 8
        default: break
        }
        if let yesterdayStrain, yesterdayStrain >= 14 { score -= 10 }
        if score >= 67 { return .push }
        if score >= 40 { return .steady }
        return .ease
    }

    // MARK: Phase review

    /// Every 3 months from the phase start, the next review date on or after today.
    static func nextPhaseReview(phase: Goals.Phase, now: Date, calendar: Calendar = .current) -> Date {
        var date = calendar.date(byAdding: .month, value: 3, to: phase.start)!
        while date < calendar.startOfDay(for: now) {
            date = calendar.date(byAdding: .month, value: 3, to: date)!
        }
        return min(date, phase.end)
    }
}
