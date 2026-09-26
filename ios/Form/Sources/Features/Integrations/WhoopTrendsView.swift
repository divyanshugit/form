import Charts
import SwiftUI

/// Last 30 days from WHOOP: recovery, sleep, day strain, and every logged activity.
struct WhoopTrendsView: View {
    @Environment(WhoopStore.self) private var whoop
    @Environment(WorkoutStore.self) private var store
    @State private var editing: WorkoutRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if whoop.days.isEmpty {
                    ContentUnavailableView("No WHOOP days yet", systemImage: "waveform.path.ecg",
                                           description: Text("Pull down to sync the last 30 days."))
                } else {
                    summary
                    recoveryChart
                    sleepChart
                    strainChart
                }
                activitiesList
                if let message = whoop.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(Palette.orangeShadow)
                }
            }
            .padding(20)
        }
        .background(Palette.bone)
        .navigationTitle("Last 30 days")
        .sheet(item: $editing) { EditWorkoutView(workout: $0) }
        .refreshable { await whoop.refresh(workouts: store) }
    }

    // MARK: Summary

    private var summary: some View {
        let recoveries = whoop.days.compactMap(\.recovery)
        let sleeps = whoop.days.compactMap(\.sleepHours)
        let green = recoveries.filter { $0 >= 67 }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("30-day read").labelStyle()
            Text(summaryLine(avgRecovery: recoveries.average, avgSleep: sleeps.average, greenDays: green))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func summaryLine(avgRecovery: Double?, avgSleep: Double?, greenDays: Int) -> String {
        var parts: [String] = []
        if let avgRecovery { parts.append("Recovery averaged \(Int(avgRecovery.rounded()))%") }
        if greenDays > 0 { parts.append("\(greenDays) green day\(greenDays == 1 ? "" : "s")") }
        if let avgSleep { parts.append(String(format: "%.1f h sleep a night", avgSleep)) }
        return parts.isEmpty ? "Not enough scored days yet." : parts.joined(separator: " · ") + "."
    }

    // MARK: Charts

    private var recoveryChart: some View {
        chartCard("Recovery", trailing: whoop.days.last?.recovery.map { "\(Int($0.rounded()))% today" }) {
            Chart(whoop.days) { day in
                if let recovery = day.recovery {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", recovery))
                        .foregroundStyle(color(for: recovery))
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 33, 67, 100]) }
        }
    }

    private var sleepChart: some View {
        chartCard("Sleep", trailing: whoop.days.last?.sleepHours.map { String(format: "%.1f h last night", $0) }) {
            Chart(whoop.days) { day in
                if let hours = day.sleepHours {
                    LineMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", hours))
                        .foregroundStyle(Palette.denim)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", hours))
                        .foregroundStyle(Palette.denim)
                        .symbolSize(18)
                }
            }
            .chartYScale(domain: 4...10)
        }
    }

    private var strainChart: some View {
        chartCard("Day strain", trailing: whoop.days.last?.dayStrain.map { String(format: "%.1f today", $0) }) {
            Chart(whoop.days) { day in
                if let strain = day.dayStrain {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Strain", strain))
                        .foregroundStyle(strain >= 14 ? Palette.orange : Palette.slate)
                        .cornerRadius(2)
                }
            }
            .chartYScale(domain: 0...21)
        }
    }

    private func chartCard<Content: View>(_ title: String, trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).labelStyle(Palette.ink)
                Spacer()
                if let trailing { Text(trailing).labelStyle() }
            }
            content()
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
        }
        .padding(18)
        .card()
    }

    /// Recovery bands in the app palette: denim for green days, slate for steady, orange for low.
    private func color(for recovery: Double) -> Color {
        switch RecoveryTone(score: recovery) {
        case .charged: Palette.denimFixed
        case .steady: Palette.slate
        case .low: Palette.orange
        }
    }

    // MARK: Activities

    private var activitiesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activities · \(whoop.activities.count)").labelStyle().padding(.bottom, 8)
            if whoop.activities.isEmpty {
                Text("No workouts logged in WHOOP in the last 30 days. Sessions you log in Form still get WHOOP heart rate once WHOOP records them.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.slateText)
            }
            ForEach(whoop.activities) { activity in
                Button {
                    editing = session(for: activity)
                } label: {
                    activityRow(activity)
                }
                .buttonStyle(.plain)
                .disabled(session(for: activity) == nil)
                .accessibilityHint("Add exercises and sets to this activity")
                Divider().overlay(Palette.rule)
            }
        }
        .padding(18)
        .card()
    }

    /// The History entry this WHOOP activity lives in: a logged session it attached to, or its own import.
    private func session(for activity: WhoopWorkout) -> WorkoutRow? {
        store.history.first { $0.whoopWorkoutId?.lowercased() == activity.id.lowercased() }
    }

    private func activityRow(_ activity: WhoopWorkout) -> some View {
        let linked = session(for: activity)
        return HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(linked?.name ?? activity.displayName).font(.headline).foregroundStyle(Palette.ink)
                        Text(activity.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .font(.footnote)
                            .foregroundStyle(Palette.slateText)
                    }
                    Spacer()
                    if let score = activity.score {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1f", score.strain)).font(.cast(.headline)).foregroundStyle(Palette.ink)
                            Text("\(score.averageHeartRate) avg · \(score.maxHeartRate) max").labelStyle()
                        }
                    }
                    Image(systemName: linked?.sortedExercises.isEmpty == false ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundStyle(linked?.sortedExercises.isEmpty == false ? Palette.denim : Palette.orange)
                        .font(.title3)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
    }
}

private extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
