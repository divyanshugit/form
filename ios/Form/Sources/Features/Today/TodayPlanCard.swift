import SwiftUI

/// Today's plan from the program: the session, readiness, the add-on skill work, protein check,
/// the week's streak and the nearest milestone.
struct TodayPlanCard: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(MetricsStore.self) private var metrics
    @Environment(WhoopStore.self) private var whoop
    let snapshot: ProgressSnapshot
    @Binding var showingWorkout: Bool
    var onScan: () -> Void
    @State private var splitsFor: WorkoutRow?

    private var plannedID: Program.TemplateID { Program.planned(on: snapshot.now) }
    private var trainedToday: [WorkoutRow] {
        Momentum.training(store.history).filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var body: some View {
        let template = Program.template(plannedID)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today · \(snapshot.block.name)").labelStyle()
                Spacer()
                if !trainedToday.isEmpty {
                    Label("Done", systemImage: "checkmark.circle.fill").labelStyle(Palette.orange)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.symbol).font(.title2.weight(.semibold)).foregroundStyle(Palette.orange).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.title2.weight(.heavy)).foregroundStyle(Palette.ink)
                    Text(template.summary).font(.subheadline).foregroundStyle(Palette.slateText)
                }
            }
            readinessRow
            actions(template)
            if let addOn = Program.addOn(on: snapshot.now).map(Program.template) {
                Button {
                    store.startWorkout(template: addOn)
                    showingWorkout = true
                } label: {
                    Label("+ \(addOn.name)", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Palette.denim)
                .disabled(store.active != nil)
            }
            Divider().overlay(Palette.rule)
            StreakRow(streak: snapshot.streak)
            proteinRow
            if let next = snapshot.closest {
                nextUp(next)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(item: $splitsFor) { HyroxSplitsView(session: $0) }
    }

    @ViewBuilder
    private func actions(_ template: Program.Template) -> some View {
        if template.isLoggable && store.active == nil && trainedToday.isEmpty {
            Button {
                store.startWorkout(template: template)
                showingWorkout = true
            } label: {
                Label("Start \(template.name.components(separatedBy: " · ").first ?? template.name)", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryKeyStyle(height: 60))
        } else if plannedID == .omniClass && trainedToday.allSatisfy({ $0.sortedExercises.isEmpty }) {
            Button(action: onScan) { Label("Scan today's board", systemImage: "text.viewfinder") }
                .buttonStyle(InkPillStyle())
        } else if plannedID == .hyroxSim, let sim = trainedToday.first(where: { $0.name.localizedCaseInsensitiveContains("hyrox") }) {
            Button { splitsFor = sim } label: { Label("Log station splits", systemImage: "stopwatch") }
                .buttonStyle(InkPillStyle())
        }
    }

    // MARK: Readiness

    private var todaySoreness: Int? { metrics.entry(MetricKind.soreness, on: .now).map { Int($0.value) } }

    private var yesterdayStrain: Double? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let strains = store.history.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: yesterday) }.compactMap(\.strain)
        return strains.isEmpty ? nil : strains.max()
    }

    private var readinessRow: some View {
        let readiness = Rules.readiness(recovery: whoop.recoveryScore, soreness: todaySoreness, yesterdayStrain: yesterdayStrain)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(readiness == .push ? Palette.orange : readiness == .steady ? Palette.denim : Palette.slateText)
                    .frame(width: 10, height: 10)
                Text(readiness.title).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                Text(readiness.detail).font(.caption).foregroundStyle(Palette.slateText).lineLimit(2)
            }
            HStack(spacing: 6) {
                Text("Sore?").font(.caption).foregroundStyle(Palette.slateText)
                ForEach(1...5, id: \.self) { level in
                    Button {
                        Task { await metrics.setDaily(MetricKind.soreness, Double(level)) }
                    } label: {
                        Text("\(level)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .frame(width: 30, height: 26)
                            .foregroundStyle(todaySoreness == level ? Palette.inkFixed : Palette.ink)
                            .background(todaySoreness == level ? Palette.orange : Palette.fog, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Text("fresh → wrecked").font(.caption2).foregroundStyle(Palette.slateText)
            }
        }
    }

    // MARK: Protein

    private var proteinRow: some View {
        let done = (metrics.entry(MetricKind.proteinOK, on: .now)?.value ?? 0) > 0
        return Button {
            Task { await metrics.setDaily(MetricKind.proteinOK, done ? 0 : 1) }
        } label: {
            HStack {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Palette.orange : Palette.slateText)
                Text("Protein ≥ \(snapshot.phase.protein.lowerBound) g today").foregroundStyle(Palette.ink)
                Spacer()
                if snapshot.proteinStreak > 1 {
                    Text("\(snapshot.proteinStreak)-day streak").font(.caption.weight(.semibold)).foregroundStyle(Palette.orange)
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    // MARK: Next up

    private func nextUp(_ status: Milestones.Status) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.milestone.track.symbol).foregroundStyle(Palette.denim).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next up · \(status.milestone.track.title)").labelStyle()
                Text(status.milestone.title + (status.best.map { " · \($0)" } ?? ""))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                if let progress = status.progress {
                    ProgressView(value: progress).tint(Palette.orange)
                }
            }
        }
    }
}
