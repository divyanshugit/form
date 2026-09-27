import SwiftUI

struct TodayView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(WhoopStore.self) private var whoop
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Binding var showingWorkout: Bool
    @State private var showingQuickLog = false
    @State private var scanning = false
    @State private var startAfterScan = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if whoop.isConnected {
                        NavigationLink {
                            WhoopTrendsView()
                        } label: {
                            recoveryCard
                        }
                        .buttonStyle(.plain)
                    } else {
                        recoveryCard
                    }
                    sessionCard
                    YearGrid(trainedDays: store.trainedDays)
                    if let last = store.history.first {
                        lastSession(last)
                    }
                    if let message = store.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.slateText)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.bone)
            .refreshable {
                await store.refresh()
                await whoop.refresh(workouts: store)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Wordmark(size: 26)
            Spacer()
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .labelStyle()
        }
        .padding(.top, 12)
    }

    /// Recovery said plainly. Before WHOOP is connected, the card is the connect button.
    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHOOP · Recovery").labelStyle(Palette.chalk.opacity(0.75))
                Spacer()
                if let created = whoop.recovery?.createdAt {
                    Text("Synced \(created.formatted(date: .omitted, time: .shortened))")
                        .labelStyle(Palette.chalk.opacity(0.75))
                }
            }
            if let score = whoop.recoveryScore {
                let tone = RecoveryTone(score: score)
                HStack(alignment: .center, spacing: 16) {
                    Text("\(Int(score.rounded()))")
                        .font(.cast(76))
                        .foregroundStyle(Palette.chalk)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tone.headline).font(.title2.weight(.bold)).foregroundStyle(Palette.chalk)
                        Text(tone.advice).font(.subheadline).foregroundStyle(Palette.chalk.opacity(0.85))
                    }
                }
                HStack {
                    Text(recoveryDetail)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Palette.chalk.opacity(0.8))
                    Spacer()
                    Text("30 days ›").labelStyle(Palette.chalk.opacity(0.9))
                }
            } else if whoop.isConnected {
                Text("Waiting on today's score.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.chalk)
                Text("WHOOP scores recovery after you wake up. Pull down to check again.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.chalk.opacity(0.8))
            } else {
                Text("Connect WHOOP")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.chalk)
                Text("Recovery and sleep show up here, and every session gets its strain and heart rate.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.chalk.opacity(0.8))
                Button {
                    Task {
                        await whoop.connect(using: webAuthenticationSession)
                        if whoop.isConnected { await whoop.refresh(workouts: store) }
                    }
                } label: {
                    if whoop.isBusy { ProgressView() } else { Text("Connect") }
                }
                .buttonStyle(PrimaryKeyStyle(height: 56))
                .padding(.top, 4)
            }
            if let message = whoop.errorMessage {
                Text(message).font(.footnote).foregroundStyle(Palette.chalk.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.navy, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .bottom) {
            Knurl(color: Palette.chalk.opacity(0.12)).frame(height: 8)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        }
        .contextMenu {
            if whoop.isConnected {
                Button("Disconnect WHOOP", systemImage: "link.badge.plus", role: .destructive) {
                    Task { await whoop.disconnect() }
                }
            }
        }
    }

    private var recoveryDetail: String {
        var parts: [String] = []
        if let score = whoop.recovery?.score {
            parts.append("HRV \(Int(score.hrvRmssdMilli.rounded())) ms")
            parts.append("RHR \(Int(score.restingHeartRate.rounded()))")
        }
        if let asleep = whoop.sleep?.asleep {
            let minutes = Int(asleep / 60)
            parts.append("Slept \(minutes / 60)h \(String(format: "%02d", minutes % 60))m")
        }
        return parts.joined(separator: " · ")
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session \(store.history.count + 1)").labelStyle()
            Text(store.active == nil ? "Ready when you are." : "You're mid-session.")
                .font(.title.weight(.heavy))
                .foregroundStyle(Palette.ink)
            Button {
                if store.active == nil { store.startWorkout() }
                showingWorkout = true
            } label: {
                Label(store.active == nil ? "Start" : "Resume", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryKeyStyle(height: 68))
            Button {
                scanning = true
            } label: {
                Label("Scan a workout board", systemImage: "text.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                showingQuickLog = true
            } label: {
                Label("Quick log a hang, plank or max reps", systemImage: "stopwatch")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .tint(Palette.denim)
        }
        .padding(18)
        .card()
        .sheet(isPresented: $showingQuickLog) { QuickLogView() }
        .sheet(isPresented: $scanning, onDismiss: {
            // Open the workout only once the scan sheet is gone, so the cover can present.
            if startAfterScan {
                startAfterScan = false
                showingWorkout = true
            }
        }) {
            ScanBoardView(confirmTitle: { store.active == nil ? "Start workout · \($0)" : "Add \($0) to workout" }) { title, exercises in
                let isNew = store.active == nil
                if isNew { store.startWorkout() }
                guard let active = store.active else { return }
                if isNew, !title.isEmpty { active.rename(title) }
                for item in exercises {
                    active.addExercise(item.exercise, reps: item.reps, seconds: item.seconds, sets: item.sets, note: item.note)
                }
                startAfterScan = true
            }
        }
        #if DEBUG
        .task { if DemoMode.scanImagePath != nil { scanning = true } }
        #endif
    }

    private func lastSession(_ workout: WorkoutRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last time · \(workout.startedAt.formatted(.relative(presentation: .named)))").labelStyle()
            Text(workout.name).font(.headline).foregroundStyle(Palette.ink)
            Text(HistorySummary.line(for: workout, library: store.library))
                .font(.subheadline)
                .foregroundStyle(Palette.slateText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A year of sessions: 53 columns × 7 days. Denim for a session, orange for today.
struct YearGrid: View {
    let trainedDays: Set<Date>

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let count = trainedDays.filter { calendar.component(.year, from: $0) == calendar.component(.year, from: today) }.count

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "\(String(calendar.component(.year, from: today))) · every mark a session").labelStyle()
                Spacer()
                Text("\(count)").font(.cast(.headline)).foregroundStyle(Palette.ink)
            }
            Canvas { context, size in
                let columns = 53, rows = 7
                let cell = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
                let start = calendar.date(byAdding: .day, value: -(columns * rows - 1), to: today)!
                for index in 0..<(columns * rows) {
                    guard let day = calendar.date(byAdding: .day, value: index, to: start) else { continue }
                    let rect = CGRect(x: CGFloat(index / rows) * cell, y: CGFloat(index % rows) * cell,
                                      width: cell * 0.62, height: cell * 0.84)
                    let color: Color = day == today ? Palette.orange
                        : trainedDays.contains(day) ? Palette.denim : Palette.rule
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
            }
            .frame(height: 64)
            .accessibilityLabel("\(count) sessions this year")
        }
        .padding(18)
        .card()
    }
}
