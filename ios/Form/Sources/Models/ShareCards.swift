import Foundation

/// What a story card says, built from real data only. Pure, so the numbers are testable;
/// `ShareCardView` draws it at 1080 × 1920.
struct ShareCardModel: Sendable {
    struct Stat: Hashable, Sendable {
        let value: String
        let label: String
    }

    struct Line: Hashable, Sendable {
        let name: String
        let detail: String
        var isPR = false
    }

    /// A stretch of the session timeline, as shares (0–1) of the session: a HYROX station or run.
    struct Segment: Hashable, Sendable {
        let label: String
        let start: Double
        let end: Double
        var isStation = true
    }

    struct Section: Sendable {
        var workoutID: UUID? = nil
        var label: String
        var hero: String
        var heroUnit: String? = nil
        /// What the hero number is: "distance", "duration".
        var heroCaption: String? = nil
        var stats: [Stat] = []
        /// Extra numbers the roomier single-session card has space for (strain, kcal).
        var details: [Stat] = []
        var lines: [Line] = []
        var zones: [Int]? = nil
        /// The session's time window, for reading heart rate from Apple Health.
        var start: Date? = nil
        var end: Date? = nil
        /// Evenly spaced bpm, drawn as the curve when present.
        var curve: [Double]? = nil
        /// The true max heart rate. The curve is averaged and smoothed, so its own top sits a few bpm lower.
        var peakBpm: Double? = nil
        /// When the max happened, as a share of the session (0–1).
        var peakAt: Double? = nil
        /// The true average (WHOOP's), so the dashed line matches the "avg bpm" stat.
        var avgBpm: Double? = nil
        /// HYROX stations and runs laid over the curve.
        var segments: [Segment] = []
        /// The previous session of the same kind, drawn faintly behind today's curve.
        var ghost: [Double]? = nil
        var ghostMinutes: Double? = nil
        var ghostLabel: String? = nil
    }

    var title: String
    var subtitle: String
    var sections: [Section] = []
    var combinedZones: [Int]? = nil
    /// Big centred statement for milestone and progress cards.
    var banner: String? = nil
    var bannerDetail: String? = nil
    var stats: [Stat] = []
    var footer: String
    /// Max heart rate the zone colours are based on.
    var maxHR: Double = 190
}

enum ShareCards {
    typealias NameLookup = (String) -> String
    /// A story card holds one to three sessions.
    static let maxSessions = 3

    // MARK: Building blocks

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "2:07" for 2 h 7 min.
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    static func pace(seconds: TimeInterval, meters: Double) -> String? {
        guard meters > 0 else { return nil }
        let perKm = seconds / (meters / 1000)
        return String(format: "%d:%02d", Int(perKm) / 60, Int(perKm) % 60)
    }

    static func hardShare(_ zones: [Int]) -> Double? {
        let total = zones.reduce(0, +)
        guard zones.count >= 6, total > 0 else { return nil }
        return Double(zones[4] + zones[5]) / Double(total)
    }

    static func combine(_ list: [[Int]]) -> [Int]? {
        let valid = list.filter { $0.count >= 6 }
        guard !valid.isEmpty else { return nil }
        return (0..<6).map { i in valid.map { $0[i] }.reduce(0, +) }
    }

    /// "8:32", "16:05": 24-hour, no leading zero.
    static func startTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }

    static func isRun(_ workout: WorkoutRow) -> Bool {
        workout.name.localizedCaseInsensitiveContains("run") && (workout.distanceM ?? 0) > 0
    }

    // MARK: Sessions

    static func section(for workout: WorkoutRow, prRefs: Set<String> = [], maxLines: Int = 7, name: NameLookup,
                        metric: Records.MetricLookup = Records.defaultMetric, calendar: Calendar = .current) -> ShareCardModel.Section {
        let weekday = workout.startedAt.formatted(.dateTime.weekday(.abbreviated))
        var section = ShareCardModel.Section(label: "\(weekday) · \(workout.name)", hero: "", zones: workout.zoneMs,
                                             start: workout.startedAt, end: workout.endedAt)
        section.peakBpm = workout.maxHr.map(Double.init)
        section.avgBpm = workout.avgHr.map(Double.init)
        section.workoutID = workout.id
        let seconds = workout.duration ?? 0
        if isRun(workout), let meters = workout.distanceM {
            section.hero = String(format: "%.2f", meters / 1000)
            section.heroUnit = "km"
            section.heroCaption = "distance"
            if let max = workout.maxHr { section.details.append(.init(value: "\(max)", label: "max bpm")) }
            section.stats.append(.init(value: duration(seconds), label: "time"))
            if let pace = pace(seconds: seconds, meters: meters) { section.stats.append(.init(value: pace, label: "/km")) }
            if let avg = workout.avgHr { section.stats.append(.init(value: "\(avg)", label: "avg bpm")) }
        } else {
            section.hero = duration(seconds)
            section.heroCaption = "duration"
            section.stats.append(.init(value: startTime(workout.startedAt), label: "start"))
            if let avg = workout.avgHr { section.stats.append(.init(value: "\(avg)", label: "avg bpm")) }
            if let max = workout.maxHr { section.stats.append(.init(value: "\(max)", label: "max bpm")) }
            if workout.avgHr == nil, let strain = workout.strain { section.stats.append(.init(value: String(format: "%.1f", strain), label: "strain")) }
        }
        if let strain = workout.strain, workout.avgHr != nil {
            section.details.append(.init(value: String(format: "%.1f", strain), label: "strain"))
        }
        if let kcal = workout.kcal { section.details.append(.init(value: "\(kcal)", label: "kcal")) }
        section.lines = workout.sortedExercises.prefix(maxLines).compactMap { exercise in
            let m = metric(exercise.exerciseRef)
            guard let best = exercise.bestSet(metric: m) else { return nil }
            let count = exercise.sortedSets.filter { $0.kind != .warmup }.count
            let weight = best.weightKg ?? 0, reps = best.reps ?? 0
            let detail: String = switch m {
            case .weightReps where weight > 0 && reps > 0: "\(count) × \(reps) · \(weight.kg) kg"
            case .bodyweightReps where weight > 0: "\(count) × \(reps) · +\(weight.kg) kg"
            default: "\(count) × " + SetFormat.describe(best, metric: m)
            }
            return .init(name: name(exercise.exerciseRef), detail: detail, isPR: prRefs.contains(exercise.exerciseRef))
        }
        return section
    }

    static func session(_ workout: WorkoutRow, prRefs: Set<String> = [], dayNumber: Int?, name: NameLookup,
                        metric: Records.MetricLookup = Records.defaultMetric) -> ShareCardModel {
        let section = section(for: workout, prRefs: prRefs, name: name, metric: metric)
        // The single-session card shows the date above the title, so the subtitle carries the rest.
        var parts: [String] = []
        let sets = workout.sortedExercises.flatMap(\.sortedSets).filter { $0.kind != .warmup }.count
        if sets > 0 { parts.append("\(workout.sortedExercises.count) exercises · \(sets) sets") }
        if !prRefs.isEmpty { parts.append("\(prRefs.count) PR\(prRefs.count == 1 ? "" : "s")") }
        return ShareCardModel(title: workout.name, subtitle: parts.joined(separator: " · "),
                              sections: [section], footer: footer(dayNumber))
    }

    /// Two or more sessions on one card, like "Going into the weekend".
    static func recap(_ workouts: [WorkoutRow], title: String? = nil, dayNumber: Int?, name: NameLookup,
                      metric: Records.MetricLookup = Records.defaultMetric, calendar: Calendar = .current) -> ShareCardModel {
        let sorted = Array(workouts.sorted { $0.startedAt < $1.startedAt }.suffix(maxSessions))
        // Fewer exercise lines per session as sessions are added, so three still fit on one story.
        let lines = sorted.count >= 3 ? 3 : sorted.count == 2 ? 4 : 7
        let total = sorted.compactMap(\.duration).reduce(0, +)
        let combined = combine(sorted.compactMap(\.zoneMs))
        var subtitle = "\(hoursMinutes(total)) trained"
        if let combined, let share = hardShare(combined) { subtitle += " · \(Int((share * 100).rounded()))% in zone 4–5" }
        return ShareCardModel(title: title ?? defaultRecapTitle(sorted, calendar: calendar), subtitle: subtitle,
                              sections: sorted.map { section(for: $0, maxLines: lines, name: name, metric: metric) },
                              combinedZones: sorted.count > 1 ? combined : nil, footer: footer(dayNumber))
    }

    static func defaultRecapTitle(_ sorted: [WorkoutRow], calendar: Calendar = .current) -> String {
        let weekdays = Set(sorted.map { calendar.component(.weekday, from: $0.startedAt) })
        if weekdays.isSubset(of: [6, 7]) && weekdays.count == 2 { return "Going into the weekend" }
        if sorted.count == 2, let first = sorted.first, let last = sorted.last, calendar.isDate(first.startedAt, inSameDayAs: last.startedAt) {
            return "Double day"
        }
        return "\(sorted.count) sessions"
    }

    // MARK: Timeline extras

    /// HYROX stations on the session timeline. Only station times are logged, so the runs share what's left
    /// of the race total evenly (one run before each station), and the race is taken to start with the session.
    static func hyroxSegments(splits: [HyroxStation: Double], total: Double?, sessionSeconds: Double) -> [ShareCardModel.Segment] {
        let stations = HyroxStation.allCases.filter { (splits[$0] ?? 0) > 0 }
        guard !stations.isEmpty, sessionSeconds > 0 else { return [] }
        let stationTime = stations.map { splits[$0]! }.reduce(0, +)
        let race = max(total ?? 0, stationTime)
        let run = max(0, race - stationTime) / Double(stations.count)
        // A race logged longer than the WHOOP session is squeezed to fit.
        let scale = race > sessionSeconds ? sessionSeconds / race : 1
        var t = 0.0
        var out: [ShareCardModel.Segment] = []
        for station in stations {
            if run > 0 {
                out.append(.init(label: "RUN", start: t * scale / sessionSeconds, end: (t + run) * scale / sessionSeconds, isStation: false))
                t += run
            }
            let length = splits[station]!
            out.append(.init(label: station.short, start: t * scale / sessionSeconds, end: (t + length) * scale / sessionSeconds))
            t += length
        }
        return out
    }

    /// The last session before this one with the same name, to compare against.
    static func previous(of workout: WorkoutRow, in history: [WorkoutRow]) -> WorkoutRow? {
        history
            .filter { $0.id != workout.id && $0.startedAt < workout.startedAt && $0.endedAt != nil
                && $0.name.caseInsensitiveCompare(workout.name) == .orderedSame }
            .max { $0.startedAt < $1.startedAt }
    }

    /// A session's logged HYROX station splits and race total, in seconds.
    static func hyroxSplits(_ rows: [MetricRow]) -> (splits: [HyroxStation: Double], total: Double?) {
        var splits: [HyroxStation: Double] = [:]
        for station in HyroxStation.allCases {
            if let row = rows.first(where: { $0.kind == station.metric }) { splits[station] = row.value }
        }
        return (splits, rows.first { $0.kind == TestKind.hyroxTotal.metric }?.value)
    }

    /// One line the session earned, for the top of the Ledger card. The first that applies wins:
    /// a PR, the biggest improvement on a HYROX station, the most zone 4–5 time in 30 days,
    /// a lower average heart rate than last time.
    static func highlight(for workout: WorkoutRow, prs: [String], splits: [HyroxStation: Double],
                          metrics: [MetricRow], history: [WorkoutRow]) -> String? {
        if prs.count == 1 { return "PR · \(prs[0])" }
        if prs.count > 1 { return "\(prs.count) PRs today" }

        var best: (station: HyroxStation, seconds: Double, gain: Double)?
        for (station, seconds) in splits where seconds > 0 {
            let earlier = metrics.filter { $0.kind == station.metric && $0.workoutId != workout.id && $0.recordedAt < workout.startedAt }
            guard let fastest = earlier.map(\.value).filter({ $0 > 0 }).min() else { continue }
            let gain = fastest - seconds
            if gain >= 1, gain > (best?.gain ?? 0) { best = (station, seconds, gain) }
        }
        if let best {
            return "Fastest \(best.station.title) yet · \(duration(best.seconds)), \(Int(best.gain.rounded())) s quicker"
        }

        func hard(_ zones: [Int]?) -> Int? {
            guard let zones, zones.count >= 6 else { return nil }
            return zones[4] + zones[5]
        }
        if let mine = hard(workout.zoneMs), mine >= 60_000 {
            let since = workout.startedAt.addingTimeInterval(-30 * 86_400)
            let others = history.filter { $0.id != workout.id && $0.startedAt >= since && $0.startedAt < workout.startedAt }
                .compactMap { hard($0.zoneMs) }
            if others.count >= 3, others.allSatisfy({ $0 < mine }) {
                return "Most zone 4–5 time in 30 days · \(Int((Double(mine) / 60_000).rounded())) min"
            }
        }

        if let previous = previous(of: workout, in: history), let now = workout.avgHr, let then = previous.avgHr, then - now >= 2 {
            return "Avg HR \(then - now) bpm lower than \(previous.startedAt.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return nil
    }

    /// "vs 2 Nov · avg −6 bpm".
    static func comparisonLabel(_ workout: WorkoutRow, previous: WorkoutRow) -> String {
        var label = "vs " + previous.startedAt.formatted(.dateTime.day().month(.abbreviated))
        if let now = workout.avgHr, let then = previous.avgHr, now != then {
            label += " · avg \(now > then ? "+" : "−")\(abs(now - then)) bpm"
        } else if let now = workout.duration, let then = previous.duration, abs(now - then) >= 30 {
            let delta = Int(((now - then) / 60).rounded())
            if delta != 0 { label += " · \(delta > 0 ? "+" : "−")\(abs(delta)) min" }
        }
        return label
    }

    // MARK: Week, milestones, progress

    static func week(_ week: Momentum.Week, streakWeeks: Int, dayNumber: Int?, name: NameLookup) -> ShareCardModel {
        let start = week.start.formatted(.dateTime.day().month(.abbreviated))
        let end = week.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated))
        var model = ShareCardModel(title: "Week in review", subtitle: "\(start) – \(end)", footer: footer(dayNumber))
        model.banner = "\(week.daysTrained) of \(week.target)"
        model.bannerDetail = week.hitTarget ? "training days. Target hit." : "training days"
        model.stats = [
            .init(value: "\(week.sessions.count)", label: "sessions"),
            .init(value: hoursMinutes(Double(week.minutes) * 60), label: "trained"),
            .init(value: "\(week.prs)", label: week.prs == 1 ? "PR" : "PRs"),
        ]
        if week.strain > 0 { model.stats.append(.init(value: String(format: "%.0f", week.strain), label: "strain")) }
        if streakWeeks > 1 { model.subtitle += " · \(streakWeeks)-week streak" }
        model.sections = week.sessions.map { workout in
            var s = ShareCardModel.Section(label: workout.startedAt.formatted(.dateTime.weekday(.abbreviated)), hero: workout.name)
            if let seconds = workout.duration { s.stats = [.init(value: hoursMinutes(seconds), label: "")] }
            return s
        }
        model.combinedZones = combine(week.sessions.compactMap(\.zoneMs))
        return model
    }

    static func milestone(_ status: Milestones.Status, dayNumber: Int?, sinceDayOne: Momentum.SinceDayOne) -> ShareCardModel {
        var model = ShareCardModel(title: "Unlocked", subtitle: status.milestone.track.title, footer: footer(dayNumber))
        model.banner = status.milestone.title
        if let date = status.achievedOn { model.bannerDetail = date.formatted(.dateTime.day().month(.wide).year()) }
        model.stats = [
            .init(value: "\(sinceDayOne.weeks)", label: "weeks in"),
            .init(value: "\(sinceDayOne.sessions)", label: "sessions"),
            .init(value: "\(sinceDayOne.prs)", label: "PRs"),
        ]
        return model
    }

    static func progress(_ since: Momentum.SinceDayOne, weightChange: Double?, milestones: Int, dayNumber: Int?) -> ShareCardModel {
        var model = ShareCardModel(title: "Since Day 1", subtitle: "\(since.weeks) weeks of showing up", footer: footer(dayNumber))
        model.banner = "\(since.daysTrained) days"
        model.bannerDetail = "trained · \(Int(since.hours.rounded())) hours"
        model.stats = [
            .init(value: "\(since.sessions)", label: "sessions"),
            .init(value: "\(since.prs)", label: "PRs"),
            .init(value: "\(milestones)", label: "milestones"),
        ]
        if let weightChange { model.stats.append(.init(value: String(format: "%+.1f", weightChange), label: "kg")) }
        return model
    }

    static func footer(_ dayNumber: Int?) -> String {
        dayNumber.map { "form · day \($0)" } ?? "form"
    }
}
