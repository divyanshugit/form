import SwiftUI

/// The 30-second weight entry: one weight per exercise for a scanned class, pre-filled with last time.
/// Reps and sets stay as the board said.
struct QuickWeightsView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutRow
    @State private var weights: [UUID: Double] = [:]

    private var weighted: [WorkoutExerciseRow] {
        workout.sortedExercises.filter { store.library.metric($0.exerciseRef) == .weightReps }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(weighted) { exercise in
                        row(exercise)
                    }
                } footer: {
                    Text(weighted.isEmpty
                         ? "No weighted exercises in this session."
                         : "Starts at what you lifted last time. Same weight goes on every set; leave 0 for bodyweight.")
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle("Weights · \(workout.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
            }
            .onAppear(perform: load)
        }
    }

    private func row(_ exercise: WorkoutExerciseRow) -> some View {
        let value = weights[exercise.id] ?? 0
        let kind = store.library.exercise(exercise.exerciseRef)?.kind ?? .other
        let step = kind == .barbell || kind == .ezBar ? 2.5 : kind == .dumbbell ? 2 : 1
        let sets = exercise.sortedSets
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.library.exercise(exercise.exerciseRef)?.name ?? exercise.exerciseRef).font(.headline)
                Spacer()
                Text("\(sets.count) × \(sets.first?.reps.map { $0 > 0 ? "\($0)" : "?" } ?? "?")")
                    .font(.system(.subheadline, design: .monospaced)).foregroundStyle(Palette.slateText)
            }
            HStack(spacing: 8) {
                Button("−\(step.kg)") { weights[exercise.id] = max(0, value - step) }.buttonStyle(StepKeyStyle())
                Text(value > 0 ? "\(value.kg) kg" : "—")
                    .font(.cast(22)).frame(minWidth: 96)
                Button("+\(step.kg)") { weights[exercise.id] = value + step }.buttonStyle(StepKeyStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        let earlier = store.history.filter { $0.startedAt < workout.startedAt }
        for exercise in weighted {
            let current = exercise.sortedSets.compactMap(\.weightKg).max() ?? 0
            let last = Records.lastSets(for: exercise.exerciseRef, in: earlier)?.compactMap(\.weightKg).max() ?? 0
            weights[exercise.id] = current > 0 ? current : last
        }
    }

    private func save() async {
        var draft = WorkoutDraft(id: workout.id, name: workout.name, startedAt: workout.startedAt, endedAt: workout.endedAt)
        draft.notes = workout.notes
        draft.exercises = workout.sortedExercises.map { row in
            let weight = weights[row.id]
            return DraftExercise(id: row.id, exerciseRef: row.exerciseRef, sets: row.sortedSets.map { set in
                DraftSet(id: set.id, kind: set.kind, weight: weight ?? set.weightKg ?? 0, reps: set.reps ?? 0,
                         completedAt: set.completedAt ?? workout.startedAt, durationSeconds: set.durationSeconds)
            }, notes: row.notes)
        }
        await store.update(draft, keeping: workout)
        dismiss()
    }
}

/// Run details for a session: distance (if WHOOP didn't measure it), time, and how it felt.
struct RunLogSheet: View {
    @Environment(MetricsStore.self) private var metrics
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutRow
    @State private var meters: Double = 6000
    @State private var rpe = 5

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(String(format: "%.2f km", meters / 1000), value: $meters, in: 0...50_000, step: 100)
                    if let duration = workout.duration {
                        LabeledContent("Time", value: ShareCards.duration(duration))
                        if let pace = ShareCards.pace(seconds: duration, meters: meters) {
                            LabeledContent("Pace", value: "\(pace) /km")
                        }
                    }
                } footer: {
                    if workout.distanceM != nil { Text("WHOOP measured this run; a value here overrides it for milestones.") }
                }
                Section("How it felt (RPE)") {
                    Picker("RPE", selection: $rpe) {
                        ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(rpe <= 4 ? "Easy, could chat" : rpe <= 6 ? "Steady" : rpe <= 8 ? "Hard" : "All out")
                        .font(.caption).foregroundStyle(Palette.slateText)
                }
            }
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await metrics.setForWorkout(MetricKind.runMeters, meters, workoutID: workout.id, at: workout.startedAt)
                            await metrics.setForWorkout(MetricKind.runRPE, Double(rpe), workoutID: workout.id, at: workout.startedAt)
                            if let duration = workout.duration {
                                await metrics.setForWorkout(MetricKind.runSeconds, duration, workoutID: workout.id, at: workout.startedAt)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                let saved = metrics.metrics(for: workout.id)
                meters = saved.first { $0.kind == MetricKind.runMeters }?.value ?? workout.distanceM ?? 6000
                rpe = saved.first { $0.kind == MetricKind.runRPE }.map { Int($0.value) } ?? 5
            }
        }
        .presentationDetents([.medium])
    }
}
