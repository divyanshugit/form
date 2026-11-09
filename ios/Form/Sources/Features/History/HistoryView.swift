import SwiftUI

struct HistoryView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(WhoopStore.self) private var whoop
    @State private var expanded: Set<UUID> = []
    @State private var editing: WorkoutRow?
    @State private var deleting: WorkoutRow?
    @State private var importingBoards = false
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var sharing: IdentifiedCard?
    @State private var weighing: WorkoutRow?
    @State private var splitting: WorkoutRow?
    @State private var running: WorkoutRow?
    @State private var viewingBoard: WorkoutRow?
    @AppStorage("history.showWalks") private var showWalks = false

    /// WHOOP logs every walk; they bury the training sessions, so they're hidden unless asked for.
    private var visible: [WorkoutRow] {
        showWalks ? store.history : store.history.filter { !HistoryFilter.isWalk($0) }
    }

    private var weeks: [(title: String, workouts: [WorkoutRow])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visible) {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt
        }
        return grouped.keys.sorted(by: >).map { start in
            let week = calendar.component(.weekOfYear, from: start)
            let items = grouped[start]!.sorted { $0.startedAt > $1.startedAt }
            return ("Week \(week) · \(items.count) session\(items.count == 1 ? "" : "s")", items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    ContentUnavailableView("No sessions yet",
                                           systemImage: "figure.strengthtraining.traditional",
                                           description: Text("Finish a workout and it lands here."))
                        .listRowBackground(Color.clear)
                }
                if let status = whoop.historyStatus {
                    HStack(spacing: 8) {
                        if whoop.isImportingHistory { ProgressView() }
                        Text(status)
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.slateText)
                    .listRowBackground(Color.clear)
                }
                if store.pendingCount > 0 {
                    Label("\(store.pendingCount) waiting to sync", systemImage: "icloud.and.arrow.up")
                        .font(.footnote)
                        .foregroundStyle(Palette.slateText)
                        .listRowBackground(Color.clear)
                }
                ForEach(weeks, id: \.title) { week in
                    Section {
                        ForEach(week.workouts) { workout in
                            row(workout)
                                .listRowBackground(Palette.card)
                                .swipeActions {
                                    Button("Delete", role: .destructive) { deleting = workout }
                                    Button("Edit") { editing = workout }
                                        .tint(Palette.denimFixed)
                                }
                                .contextMenu {
                                    Button(workout.isWhoopImport ? "Define session" : "Edit session", systemImage: "pencil") {
                                        editing = workout
                                    }
                                    Button("Share card", systemImage: "square.and.arrow.up") { share([workout]) }
                                    if workout.sortedExercises.contains(where: { store.library.metric($0.exerciseRef) == .weightReps }) {
                                        Button("Fill in weights", systemImage: "scalemass") { weighing = workout }
                                    }
                                    if workout.name.localizedCaseInsensitiveContains("hyrox") {
                                        Button("HYROX splits", systemImage: "stopwatch") { splitting = workout }
                                    }
                                    if workout.name.localizedCaseInsensitiveContains("run") {
                                        Button("Run details", systemImage: "figure.run") { running = workout }
                                    }
                                    if BoardPhotos.exists(for: workout.id) {
                                        Button("Board photo", systemImage: "photo") { viewingBoard = workout }
                                    }
                                }
                        }
                    } header: {
                        Text(week.title).labelStyle()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle("History")
            .sheet(item: $editing) { workout in
                EditWorkoutView(workout: workout)
            }
            .confirmationDialog(
                "Delete \(deleting?.name ?? "session")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { workout in
                Button("Delete session", role: .destructive) {
                    Task { await store.delete(workout) }
                }
            } message: { workout in
                Text(workout.isWhoopImport
                     ? "It'll come back on the next full WHOOP import."
                     : "Its exercises and sets are removed for good.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? "Cancel" : "Share") {
                        selecting.toggle()
                        selection = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import board photos", systemImage: "photo.stack") { importingBoards = true }
                    Toggle(isOn: $showWalks) { Label("Show walks", systemImage: "figure.walk") }
                    if whoop.isConnected {
                        Button("Import all WHOOP history", systemImage: "arrow.down.circle") {
                            Task { await whoop.importHistory(workouts: store) }
                        }
                        .disabled(whoop.isImportingHistory)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("History options")
                }
            }
            .sheet(isPresented: $importingBoards) { BoardImportView() }
            .sheet(item: $sharing) { ShareCardSheet(model: $0.model) }
            .sheet(item: $weighing) { QuickWeightsView(workout: $0) }
            .sheet(item: $splitting) { HyroxSplitsView(session: $0) }
            .sheet(item: $running) { RunLogSheet(workout: $0) }
            .sheet(item: $viewingBoard) { workout in
                NavigationStack {
                    ScrollView {
                        if let image = BoardPhotos.image(for: workout.id) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                    }
                    .background(Palette.midnight)
                    .navigationTitle(workout.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    Button {
                        share(store.history.filter { selection.contains($0.id) })
                    } label: {
                        Label(selection.isEmpty ? "Pick up to \(ShareCards.maxSessions) sessions"
                              : "Share \(selection.count) of \(ShareCards.maxSessions) on one card",
                              systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryKeyStyle(height: 56))
                    .disabled(selection.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .refreshable {
                await store.refresh()
                await whoop.refresh(workouts: store)
            }
        }
    }

    private func share(_ workouts: [WorkoutRow]) {
        guard !workouts.isEmpty else { return }
        let name: ShareCards.NameLookup = { store.library.exercise($0)?.name ?? $0 }
        let day = ProgressSnapshot.dayNumber(workouts.map(\.startedAt).max() ?? .now)
        if workouts.count == 1, let workout = workouts.first {
            let prs = Set(Momentum.prEvents(history: store.history).filter { $0.date == workout.startedAt }.map(\.ref))
            sharing = IdentifiedCard(model: ShareCards.session(workout, prRefs: prs, dayNumber: day, name: name))
        } else {
            sharing = IdentifiedCard(model: ShareCards.recap(workouts, dayNumber: day, name: name))
        }
        selecting = false
        selection = []
    }

    private func row(_ workout: WorkoutRow) -> some View {
        let isOpen = expanded.contains(workout.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if selecting {
                    if selection.contains(workout.id) {
                        selection.remove(workout.id)
                    } else if selection.count < ShareCards.maxSessions {
                        selection.insert(workout.id)
                    }
                    return
                }
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(workout.id) } else { expanded.insert(workout.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    if selecting {
                        let full = selection.count >= ShareCards.maxSessions && !selection.contains(workout.id)
                        Image(systemName: selection.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selection.contains(workout.id) ? Palette.orange : Palette.rule)
                            .opacity(full ? 0.4 : 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(workout.name).font(.headline).foregroundStyle(Palette.ink)
                            if workout.isWhoopImport {
                                Text("WHOOP")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .foregroundStyle(Palette.chalk)
                                    .background(Palette.navy, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(HistorySummary.line(for: workout, library: store.library))
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day()))
                            .labelStyle(Palette.ink)
                        if let duration = workout.duration {
                            Text("\(Int(duration / 60)) min").labelStyle()
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen, workout.strain != nil {
                HeartRateStrip(workout: workout)
            }
            if isOpen, let zones = workout.zoneMs, zones.reduce(0, +) > 0 {
                ZoneBar(zones: zones, height: 6, labelSize: 10, labelColor: Palette.slateText)
                    .padding(.vertical, 4)
            }
            if isOpen, !selecting {
                Button { share([workout]) } label: {
                    Label("Story card", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Palette.orange)
            }
            if isOpen, BoardPhotos.exists(for: workout.id) {
                Button { viewingBoard = workout } label: {
                    Label("Board photo", systemImage: "photo").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Palette.denim)
            }
            if isOpen, workout.sortedExercises.contains(where: { exercise in
                store.library.metric(exercise.exerciseRef) == .weightReps
                    && exercise.sortedSets.allSatisfy { ($0.weightKg ?? 0) == 0 }
            }) {
                Button { weighing = workout } label: {
                    Label("Fill in weights · 30 seconds", systemImage: "scalemass").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Palette.orange)
            }
            if isOpen, workout.isWhoopImport, workout.sortedExercises.isEmpty {
                Button {
                    editing = workout
                } label: {
                    Label("Define this session: name it, add exercises and sets", systemImage: "pencil.line")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Palette.denim)
            }
            if isOpen {
                ForEach(workout.sortedExercises) { exercise in
                    HStack {
                        Text(store.library.exercise(exercise.exerciseRef)?.name ?? exercise.exerciseRef)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(exercise.sortedSets.map { SetFormat.describe($0, metric: store.library.metric(exercise.exerciseRef)) }.joined(separator: "  "))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.slateText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

enum HistorySummary {
    /// "Bench Press 82.5 × 8 · 18 sets" — the one line that says what happened.
    static func line(for workout: WorkoutRow, library: ExerciseLibrary) -> String {
        let base = liftLine(for: workout, library: library)
        guard let strain = workout.strain else { return base }
        let whoop = "strain \(String(format: "%.1f", strain))" + (workout.avgHr.map { " · \($0) bpm" } ?? "")
        return workout.isWhoopImport ? whoop : "\(base) · \(whoop)"
    }

    private static func liftLine(for workout: WorkoutRow, library: ExerciseLibrary) -> String {
        let setCount = workout.sortedExercises.reduce(0) { $0 + ($1.sets?.count ?? 0) }
        guard let first = workout.sortedExercises.first, let top = first.topSet else {
            return "\(setCount) sets"
        }
        let name = library.exercise(first.exerciseRef)?.name ?? first.exerciseRef
        let best = first.bestSet(metric: library.metric(first.exerciseRef)) ?? top
        return "\(name) \(SetFormat.describe(best, metric: library.metric(first.exerciseRef))) · \(setCount) set\(setCount == 1 ? "" : "s")"
    }
}


/// WHOOP numbers for a session: strain, average and max heart rate, calories.
struct HeartRateStrip: View {
    let workout: WorkoutRow

    var body: some View {
        HStack(spacing: 0) {
            cell(workout.strain.map { String(format: "%.1f", $0) }, "strain")
            cell(workout.avgHr.map(String.init), "avg bpm")
            cell(workout.maxHr.map(String.init), "max bpm")
            cell(workout.kcal.map(String.init), "kcal")
        }
        .padding(.vertical, 10)
        .background(Palette.fog, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func cell(_ value: String?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value ?? "–").font(.cast(.headline)).foregroundStyle(Palette.ink)
            Text(label).labelStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
