import SwiftUI

/// One skill ladder: done steps ticked, the next one with progress, later ones dimmed.
struct MilestoneTrackCard: View {
    @Environment(MetricsStore.self) private var metrics
    let track: Milestone.Track
    let statuses: [Milestones.Status]
    var onShare: (Milestones.Status) -> Void = { _ in }

    var body: some View {
        let next = statuses.first { !$0.isDone }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(track.title, systemImage: track.symbol).labelStyle()
                Spacer()
                Text("\(statuses.filter(\.isDone).count)/\(statuses.count)").labelStyle()
            }
            ForEach(statuses) { status in
                row(status, isNext: status.id == next?.id)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ status: Milestones.Status, isNext: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status.isDone ? "checkmark.seal.fill" : isNext ? "circle.dashed" : "circle")
                .font(.title3)
                .foregroundStyle(status.isDone ? Palette.orange : isNext ? Palette.ink : Palette.rule)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.milestone.title)
                    .font(.subheadline.weight(isNext ? .bold : .regular))
                    .foregroundStyle(status.isDone || isNext ? Palette.ink : Palette.slateText)
                if let date = status.achievedOn {
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption).foregroundStyle(Palette.slateText)
                } else if isNext {
                    if let progress = status.progress {
                        ProgressView(value: progress).tint(Palette.orange).frame(maxWidth: 180)
                    }
                    if let best = status.best {
                        Text(best).font(.caption).foregroundStyle(Palette.slateText)
                    } else if status.milestone.rule == .manual {
                        Text("Tick it when you get it").font(.caption).foregroundStyle(Palette.slateText)
                    }
                }
            }
            Spacer()
            if status.isDone {
                Button { onShare(status) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
                    .tint(Palette.denim)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            let manual = metrics.rows.first { $0.kind == status.milestone.manualKind }
            if let manual {
                Button("Untick", systemImage: "xmark.circle", role: .destructive) { Task { await metrics.delete(manual.id) } }
            } else if !status.isDone {
                Button("Mark as done", systemImage: "checkmark.circle") {
                    Task { await metrics.record(status.milestone.manualKind, 1) }
                }
            }
        }
    }
}

/// Full-screen moment when a milestone ticks for the first time.
struct MilestoneUnlockedView: View {
    @Environment(\.dismiss) private var dismiss
    let status: Milestones.Status
    let dayNumber: Int
    let since: Momentum.SinceDayOne
    @State private var sharing = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Palette.navy.ignoresSafeArea()
            Circle().fill(Palette.orange.opacity(0.25)).frame(width: 520).blur(radius: 90).offset(y: -120)
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: status.milestone.track.symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Palette.orange)
                    .scaleEffect(appeared ? 1 : 0.4)
                Text("UNLOCKED").labelStyle(Palette.chalk.opacity(0.8))
                Text(status.milestone.title)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.chalk)
                Text("\(status.milestone.track.title) · day \(dayNumber) · \(since.sessions) sessions in")
                    .font(.subheadline)
                    .foregroundStyle(Palette.chalk.opacity(0.8))
                Spacer()
                Button { sharing = true } label: { Label("Share it", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
                Button("Keep going") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(Palette.chalk)
                    .padding(.bottom, 12)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .sheet(isPresented: $sharing) {
            ShareCardSheet(model: ShareCards.milestone(status, dayNumber: dayNumber, sinceDayOne: since))
        }
    }
}

/// Remembers which milestones have been celebrated, so each gets its moment once.
enum Celebrations {
    private static let key = "milestones.celebrated"

    /// Call only once history has loaded. Only milestones reached in the last two weeks get a moment.
    static func pending(_ statuses: [Milestones.Status], now: Date = .now, defaults: UserDefaults = .standard) -> Milestones.Status? {
        let done = statuses.filter(\.isDone)
        guard !done.isEmpty else { return nil }
        guard let seen = defaults.stringArray(forKey: key) else {
            // First run: everything already achieved counts as celebrated.
            defaults.set(done.map(\.id), forKey: key)
            return nil
        }
        let recent = now.addingTimeInterval(-14 * 86_400)
        return done.filter { !seen.contains($0.id) && ($0.achievedOn ?? .distantPast) > recent }.max { ($0.achievedOn ?? .distantPast) < ($1.achievedOn ?? .distantPast) }
    }

    static func markSeen(_ id: String, defaults: UserDefaults = .standard) {
        defaults.set((defaults.stringArray(forKey: key) ?? []) + [id], forKey: key)
    }
}
