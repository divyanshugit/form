import Foundation

/// The "you're making progress" numbers: since Day 1, this week, streaks and PRs over time. Pure.
enum Momentum {
    /// Sessions that count as training: everything except undefined WHOOP walks.
    static func training(_ history: [WorkoutRow]) -> [WorkoutRow] {
        history.filter { !HistoryFilter.isWalk($0) }
    }

    // MARK: Since Day 1

    struct SinceDayOne: Sendable {
        var firstDay: Date?
        var daysTrained = 0
        var sessions = 0
        var hours = 0.0
        var prs = 0
        var weeks = 0
        var hyroxSims = 0
        var kilometres = 0.0
    }

    static func sinceDayOne(history: [WorkoutRow], now: Date = .now, calendar: Calendar = .current,
                            metric: Records.MetricLookup = Records.defaultMetric) -> SinceDayOne {
        let sessions = training(history)
        var result = SinceDayOne()
        result.firstDay = sessions.map(\.startedAt).min()
        result.sessions = sessions.count
        result.daysTrained = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).count
        result.hours = sessions.compactMap(\.duration).reduce(0, +) / 3600
        result.prs = prEvents(history: sessions, metric: metric).count
        result.weeks = result.firstDay.map { Goals.weeks(from: $0, to: now) } ?? 0
        result.hyroxSims = sessions.filter { $0.name.localizedCaseInsensitiveContains("hyrox") }.count
        result.kilometres = sessions.filter { $0.name.localizedCaseInsensitiveContains("run") }
            .compactMap(\.distanceM).reduce(0, +) / 1000
        return result
    }

    /// Every time an exercise beat its previous best (the first session of an exercise doesn't count).
    static func prEvents(history: [WorkoutRow], metric: Records.MetricLookup = Records.defaultMetric) -> [(date: Date, ref: String)] {
        var best: [String: Double] = [:]
        var events: [(Date, String)] = []
        for workout in history.sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in workout.sortedExercises {
                let sets = exercise.sortedSets.filter { $0.kind != .warmup }
                let value: Double = switch metric(exercise.exerciseRef) {
                case .duration: Double(sets.map { $0.durationSeconds ?? 0 }.max() ?? 0)
                case .bodyweightReps: Double(sets.map { $0.reps ?? 0 }.max() ?? 0)
                case .weightReps: sets.filter { ($0.weightKg ?? 0) > 0 }
                    .map { PlateMath.estimatedOneRepMax(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }.max() ?? 0
                }
                guard value > 0 else { continue }
                if let previous = best[exercise.exerciseRef] {
                    if value > previous + 0.001 {
                        events.append((workout.startedAt, exercise.exerciseRef))
                        best[exercise.exerciseRef] = value
                    }
                } else {
                    best[exercise.exerciseRef] = value
                }
            }
        }
        return events
    }

    // MARK: Weeks

    static func mondayCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
        let monday = mondayCalendar(calendar)
        return monday.dateInterval(of: .weekOfYear, for: date)!.start
    }

    struct Week: Sendable {
        var start: Date
        var sessions: [WorkoutRow] = []
        var daysTrained = 0
        var minutes = 0
        var strain = 0.0
        var kcal = 0
        var prs = 0
        /// Minutes in WHOOP zones 4–5.
        var hardMinutes = 0
        var target = 5

        var end: Date { start.addingTimeInterval(7 * 86_400) }
        var hitTarget: Bool { daysTrained >= target }
    }

    static func week(containing date: Date, history: [WorkoutRow], calendar: Calendar = .current,
                     metric: Records.MetricLookup = Records.defaultMetric) -> Week {
        let start = weekStart(date, calendar: calendar)
        var week = Week(start: start)
        let all = training(history)
        week.sessions = all.filter { $0.startedAt >= start && $0.startedAt < week.end }.sorted { $0.startedAt < $1.startedAt }
        week.daysTrained = Set(week.sessions.map { calendar.startOfDay(for: $0.startedAt) }).count
        week.minutes = Int(week.sessions.compactMap(\.duration).reduce(0, +) / 60)
        week.strain = week.sessions.compactMap(\.strain).reduce(0, +)
        week.kcal = week.sessions.compactMap(\.kcal).reduce(0, +)
        week.hardMinutes = week.sessions.compactMap(\.zoneMs).map { zones in
            zones.count >= 6 ? (zones[4] + zones[5]) / 60_000 : 0
        }.reduce(0, +)
        week.prs = prEvents(history: all, metric: metric).filter { $0.date >= start && $0.date < week.end }.count
        // A week's target belongs to the block it starts in, but travel weeks count as travel if any day is.
        let midweek = start.addingTimeInterval(3.5 * 86_400)
        week.target = min(Goals.block(on: start).weeklyTarget, Goals.block(on: midweek).weeklyTarget)
        return week
    }

    // MARK: Streaks

    struct Streak: Sendable {
        /// Consecutive weeks hitting the target, counting this week once it's hit.
        var weeks = 0
        /// Training days this week and the week's target.
        var thisWeek = 0
        var target = 5
        /// Best run of weeks ever.
        var best = 0
    }

    /// Weekly streak. The target already leaves room for a missed day (5 of 6 planned days),
    /// which is the grace day: one missed class never breaks it. The current week only breaks
    /// the streak once it's over.
    static func weeklyStreak(history: [WorkoutRow], now: Date = .now, calendar: Calendar = .current) -> Streak {
        let all = training(history)
        guard let first = all.map(\.startedAt).min() else {
            return Streak(target: Goals.block(on: now).weeklyTarget)
        }
        let monday = mondayCalendar(calendar)
        var weekStart = self.weekStart(first, calendar: calendar)
        let current = self.weekStart(now, calendar: calendar)
        var run = 0, best = 0
        var streak = Streak()
        while weekStart <= current {
            let week = week(containing: weekStart, history: all, calendar: calendar, metric: { _ in .weightReps })
            if weekStart == current {
                streak.thisWeek = week.daysTrained
                streak.target = week.target
                if week.hitTarget { run += 1 }
            } else {
                run = week.hitTarget ? run + 1 : 0
            }
            best = max(best, run)
            weekStart = monday.date(byAdding: .weekOfYear, value: 1, to: weekStart)!
        }
        streak.weeks = run
        streak.best = best
        return streak
    }

    /// Consecutive days with a check-in (protein ≥ target), allowing one missed day per Monday week.
    static func dailyStreak(days: Set<Date>, now: Date = .now, calendar: Calendar = .current) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: now)
        // Today without a check-in yet doesn't break anything.
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var missesThisWeek: [Date: Int] = [:]
        while true {
            let week = weekStart(day, calendar: calendar)
            if days.contains(day) {
                count += 1
            } else {
                let misses = missesThisWeek[week, default: 0]
                guard misses == 0, count > 0 else { break }
                missesThisWeek[week] = 1
            }
            day = calendar.date(byAdding: .day, value: -1, to: day)!
            if count == 0 && !days.contains(day) && missesThisWeek.isEmpty { break }
        }
        return count
    }
}
