import SwiftUI

/// Sunday review: the week's numbers and what the decision rules say to do next.
struct WeeklyReviewView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(MetricsStore.self) private var metrics
    @Environment(PhotoStore.self) private var photos
    @Environment(WhoopStore.self) private var whoop
    @State private var sharing = false

    var body: some View {
        let snapshot = ProgressSnapshot(store: store, metrics: metrics, photos: photos)
        let input = Rules.Input(now: .now, history: store.history, weights: snapshot.weights, waists: snapshot.waists,
                                recoveries: whoop.days.compactMap { day in day.recovery.map { (day.date, $0) } },
                                lastDeload: metrics.latest(MetricKind.deload)?.recordedAt)
        let trends = Rules.trends(input)
        let suggestions = Rules.weeklyReview(input)
        let week = snapshot.week

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This week").labelStyle()
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        stat("\(week.daysTrained)/\(week.target)", "days")
                        stat("\(week.sessions.count)", "sessions")
                        stat(ShareCards.hoursMinutes(Double(week.minutes) * 60), "trained")
                        stat("\(week.prs)", "PRs")
                    }
                    StreakRow(streak: snapshot.streak)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Trends").labelStyle()
                    trend("Weight", trends.weightPerMonth.map { String(format: "%+.1f kg / month", $0) } ?? "Need 4 weeks of weigh-ins")
                    trend("Waist", trends.waistChange.map { String(format: "%+.1f cm in 4 weeks", $0) } ?? "Need two measurements")
                    trend("Strength", trends.strengthUp ? "\(trends.prsLast14) PRs in 2 weeks"
                          : trends.strengthFlat ? "No PRs in 3 weeks" : "\(trends.prsLast21) PRs in 3 weeks")
                    if let avg = MetricMath.average(snapshot.weights, endingAt: .now) {
                        trend("7-day avg", String(format: "%.1f kg", avg))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Text("What to do").labelStyle().padding(.top, 4)
                if suggestions.isEmpty {
                    Text("Nothing to change. Keep logging and the rules will speak up when the trend does.")
                        .font(.subheadline).foregroundStyle(Palette.slateText)
                }
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.title).font(.headline).foregroundStyle(suggestion.kind == .keepGoing ? Palette.chalk : Palette.ink)
                        Text(suggestion.detail).font(.subheadline)
                            .foregroundStyle(suggestion.kind == .keepGoing ? Palette.chalk.opacity(0.85) : Palette.slateText)
                        if suggestion.kind == .deload {
                            Button("Start deload week today") { Task { await metrics.record(MetricKind.deload, 1) } }
                                .buttonStyle(InkPillStyle())
                                .padding(.top, 4)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(suggestion.kind == .keepGoing ? Palette.navy : Palette.card)
                }

                Button { sharing = true } label: { Label("Share the week", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.bone)
        .navigationTitle("Weekly review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $sharing) {
            ShareCardSheet(model: ShareCards.week(week, streakWeeks: snapshot.streak.weeks, dayNumber: snapshot.dayNumber,
                                                 name: { store.library.exercise($0)?.name ?? $0 }))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.cast(24)).foregroundStyle(Palette.ink)
            Text(label).font(.caption).foregroundStyle(Palette.slateText)
        }
    }

    private func trend(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.slateText)
            Spacer()
            Text(value).foregroundStyle(Palette.ink)
        }
        .font(.subheadline)
    }
}
