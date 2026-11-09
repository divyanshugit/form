import Charts
import SwiftUI

/// The Goals tab: phase and exit criteria, this block, body measures, baseline tests, milestones.
struct GoalsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(MetricsStore.self) private var metrics
    @Environment(PhotoStore.self) private var photos

    @State private var measuring: MeasureSheet.Kind?
    @State private var sharing: ShareCardModel?
    @State private var celebrating: Milestones.Status?

    var body: some View {
        let snapshot = ProgressSnapshot(store: store, metrics: metrics, photos: photos)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(snapshot)
                    PhaseCard(snapshot: snapshot, expanded: true)
                    blockCard(snapshot)
                    links(snapshot)
                    bodyCard(snapshot)
                    NavigationLink { TestDaysView() } label: { testDaysRow }
                        .buttonStyle(.plain)
                    ForEach(Milestone.Track.allCases) { track in
                        MilestoneTrackCard(track: track, statuses: snapshot.milestones.filter { $0.milestone.track == track },
                                           onShare: { status in
                                               sharing = ShareCards.milestone(status, dayNumber: snapshot.dayNumber, sinceDayOne: snapshot.since)
                                           })
                    }
                    if let message = metrics.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.slateText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.bone)
            .refreshable { await metrics.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $measuring) { kind in MeasureSheet(kind: kind) }
            .sheet(item: Binding(get: { sharing.map(IdentifiedCard.init) }, set: { sharing = $0?.model })) { card in
                ShareCardSheet(model: card.model)
            }
        }
    }

    private func header(_ snapshot: ProgressSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Goals").font(.cast(30)).foregroundStyle(Palette.ink)
            Spacer()
            Text("Day \(snapshot.dayNumber)").labelStyle()
        }
        .padding(.top, 12)
    }

    private func blockCard(_ snapshot: ProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Now · \(snapshot.block.name)").labelStyle()
                Spacer()
                if let end = snapshot.block.end {
                    Text("until \(end.formatted(.dateTime.day().month(.abbreviated)))").labelStyle()
                }
            }
            Text(snapshot.block.aim).font(.headline).foregroundStyle(Palette.ink)
            StreakRow(streak: snapshot.streak)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func links(_ snapshot: ProgressSnapshot) -> some View {
        VStack(spacing: 0) {
            NavigationLink { SinceDayOneView() } label: {
                linkRow("Since Day 1", detail: "\(snapshot.since.daysTrained) days · \(snapshot.since.prs) PRs", symbol: "sunrise")
            }
            Divider().overlay(Palette.rule)
            NavigationLink { WeeklyReviewView() } label: {
                linkRow("Weekly review", detail: "What the numbers say to do next", symbol: "checklist")
            }
            Divider().overlay(Palette.rule)
            Button {
                sharing = ShareCards.week(snapshot.week, streakWeeks: snapshot.streak.weeks, dayNumber: snapshot.dayNumber,
                                          name: { store.library.exercise($0)?.name ?? $0 })
            } label: {
                linkRow("Share this week", detail: "\(snapshot.week.daysTrained) of \(snapshot.week.target) days so far", symbol: "square.and.arrow.up")
            }
            Divider().overlay(Palette.rule)
            Button {
                sharing = ShareCards.progress(snapshot.since, weightChange: snapshot.weightChange,
                                              milestones: snapshot.achievedCount, dayNumber: snapshot.dayNumber)
            } label: {
                linkRow("Share progress card", detail: "Since Day 1, on one story", symbol: "photo.on.rectangle")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .card()
    }

    private func linkRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(detail).font(.subheadline).foregroundStyle(Palette.slateText)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.slateText)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func bodyCard(_ snapshot: ProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Body").labelStyle()
                Spacer()
                if let change = snapshot.weightChange {
                    Text(String(format: "%+.1f kg since first weigh-in", change)).labelStyle()
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                measure("Weight", value: MetricMath.average(snapshot.weights, endingAt: .now).map { String(format: "%.1f", $0) },
                        unit: "kg · 7-day avg")
                measure("Waist", value: snapshot.waists.last.map { String(format: "%.1f", $0.value) }, unit: "cm")
            }
            if snapshot.weights.count > 1 {
                WeightChart(points: snapshot.weights).frame(height: 140)
            }
            HStack(spacing: 10) {
                Button("Log weight") { measuring = .weight }.buttonStyle(InkPillStyle())
                Button("Log waist") { measuring = .waist }.buttonStyle(InkPillStyle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func measure(_ title: String, value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—").font(.cast(34)).foregroundStyle(Palette.ink)
            Text("\(title) · \(unit)").font(.caption).foregroundStyle(Palette.slateText)
        }
    }

    private var testDaysRow: some View {
        let logged = TestKind.allCases.filter { PhaseProgress.baseline($0, metrics: metrics.rows) != nil }.count
        return HStack(spacing: 14) {
            Image(systemName: "flag.checkered").font(.title3).foregroundStyle(Palette.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Baseline tests · Nov 27–30").font(.headline).foregroundStyle(Palette.ink)
                Text(logged == 0 ? "Run, HYROX sim, strength and body" : "\(logged) results logged")
                    .font(.subheadline).foregroundStyle(Palette.slateText)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.slateText)
        }
        .padding(18)
        .card()
    }
}

/// Lets an optional model drive `.sheet(item:)`.
struct IdentifiedCard: Identifiable {
    let id = UUID()
    let model: ShareCardModel
}

// MARK: - Phase card

struct PhaseCard: View {
    @Environment(MetricsStore.self) private var metrics
    let snapshot: ProgressSnapshot
    var expanded = false

    var body: some View {
        let phase = snapshot.phase
        let met = snapshot.criteria.filter(\.met).count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Phase \(phaseNumber) · \(phase.name)").labelStyle(Palette.chalk.opacity(0.8))
                Spacer()
                Text("\(snapshot.weeksLeftInPhase) weeks left").labelStyle(Palette.chalk.opacity(0.8))
            }
            Text(phase.focus).font(.title3.weight(.bold)).foregroundStyle(Palette.chalk)
            ProgressView(value: PhaseProgress.elapsed(phase, now: snapshot.now))
                .tint(Palette.orange)
            HStack {
                Text("\(met)/\(phase.exit.count) criteria")
                Spacer()
                Text("\(phase.kcal.lowerBound == phase.kcal.upperBound ? "\(phase.kcal.lowerBound)" : "\(phase.kcal.lowerBound)–\(phase.kcal.upperBound)") kcal · \(phase.protein.lowerBound) g protein")
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Palette.chalk.opacity(0.85))
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.criteria) { status in
                        Button {
                            guard case .manual = status.criterion.check else { return }
                            Task { await toggle(status) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: status.met ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(status.met ? Palette.orange : Palette.chalk.opacity(0.6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(status.criterion.title).foregroundStyle(Palette.chalk)
                                    if let detail = status.detail {
                                        Text(detail).font(.caption).foregroundStyle(Palette.chalk.opacity(0.7))
                                    }
                                }
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
                Text("Next phase review \(Rules.nextPhaseReview(phase: phase, now: snapshot.now).formatted(.dateTime.day().month(.wide).year()))")
                    .font(.caption).foregroundStyle(Palette.chalk.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.navy, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var phaseNumber: Int { (Goals.phases.firstIndex { $0.id == snapshot.phase.id } ?? 0) + 1 }

    private func toggle(_ status: PhaseProgress.CriterionStatus) async {
        let kind = MetricKind.milestone(status.criterion.id)
        if let existing = metrics.rows.first(where: { $0.kind == kind }) {
            await metrics.delete(existing.id)
        } else {
            await metrics.record(kind, 1)
        }
    }
}

struct StreakRow: View {
    let streak: Momentum.Streak

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<max(streak.target, streak.thisWeek), id: \.self) { i in
                    Capsule()
                        .fill(i < streak.thisWeek ? Palette.orange : Palette.rule)
                        .frame(width: 16, height: 8)
                }
            }
            Text("\(streak.thisWeek)/\(streak.target) this week")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            if streak.weeks > 0 {
                Label("\(streak.weeks) wk", systemImage: "flame.fill")
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.orange)
            }
        }
    }
}

// MARK: - Weight chart

struct WeightChart: View {
    let points: [(date: Date, value: Double)]

    var body: some View {
        let average = MetricMath.movingAverage(points)
        let values = points.map(\.value)
        let low = (values.min() ?? 60) - 0.8, high = (values.max() ?? 80) + 0.8
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Day", point.date), y: .value("kg", point.value))
                    .foregroundStyle(Palette.slateText.opacity(0.35))
                    .symbolSize(18)
            }
            ForEach(Array(average.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Day", point.date), y: .value("7-day", point.value))
                    .foregroundStyle(Palette.orange)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartYScale(domain: low...high)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
    }
}

// MARK: - Measure entry

struct MeasureSheet: View {
    enum Kind: String, Identifiable {
        case weight, waist
        var id: String { rawValue }
    }

    @Environment(MetricsStore.self) private var metrics
    @Environment(\.dismiss) private var dismiss
    let kind: Kind
    @State private var value: Double = 0
    @State private var date = Date.now

    private var metricKind: String { kind == .weight ? MetricKind.weight : MetricKind.waist }
    private var step: Double { kind == .weight ? 0.1 : 0.5 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(kind == .weight ? "Morning, after the bathroom, before food." : "At the navel, relaxed, morning.")
                    .font(.subheadline).foregroundStyle(Palette.slateText)
                Text(String(format: kind == .weight ? "%.1f" : "%.1f", value))
                    .font(.cast(72)).foregroundStyle(Palette.ink)
                    + Text(kind == .weight ? " kg" : " cm").font(.title2).foregroundStyle(Palette.slateText)
                HStack(spacing: 10) {
                    ForEach([-1.0, -step, step, 1.0], id: \.self) { delta in
                        Button(delta > 0 ? "+\(delta.kg)" : "−\((-delta).kg)") { value = max(0, (value + delta) * 10).rounded() / 10 }
                            .buttonStyle(StepKeyStyle())
                    }
                }
                DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: .date)
                Spacer()
                Button("Save") {
                    Task {
                        await metrics.setDaily(metricKind, value, on: date)
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryKeyStyle(height: 60))
                .disabled(value <= 0)
            }
            .padding(20)
            .background(Palette.bone)
            .navigationTitle(kind == .weight ? "Weight" : "Waist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                value = metrics.latest(metricKind)?.value ?? (kind == .weight ? Goals.baselineWeightKg : 78)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
