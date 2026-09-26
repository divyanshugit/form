import SwiftUI

/// Log a result without starting a workout: a hang test, max push-ups, a plank before bed.
struct QuickLogView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var exercise: Exercise?
    @State private var date = Date.now
    @State private var sets: [DraftSet] = []
    @State private var showingPicker = false

    init(exercise: Exercise? = nil) {
        _exercise = State(initialValue: exercise)
    }

    private var metric: ExerciseMetric { exercise?.metric ?? .weightReps }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Text("Exercise").foregroundStyle(Palette.ink)
                            Spacer()
                            Text(exercise?.name ?? "Choose").foregroundStyle(Palette.slateText)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.slateText)
                        }
                    }
                    DatePicker("When", selection: $date, in: ...Date.now)
                }

                if exercise != nil {
                    Section {
                        ForEach($sets) { $set in
                            QuickSetRow(set: $set, metric: metric)
                        }
                        .onDelete { sets.remove(atOffsets: $0) }
                        Button("Add another set", systemImage: "plus") {
                            sets.append(sets.last.map {
                                DraftSet(weight: $0.weight, reps: $0.reps, durationSeconds: $0.durationSeconds)
                            } ?? defaultSet(for: exercise))
                        }
                    } header: {
                        Text(metric == .duration ? "Hold time" : metric == .bodyweightReps ? "Reps" : "Sets")
                    } footer: {
                        if let best = bestLine { Text(best) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle("Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(exercise == nil || sets.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { picked in
                    exercise = picked
                    sets = [prefill(for: picked)]
                }
            }
            .onAppear {
                if let exercise, sets.isEmpty { sets = [prefill(for: exercise)] }
            }
        }
    }

    private var bestLine: String? {
        guard let exercise, let best = store.bests[exercise.id] else { return nil }
        switch metric {
        case .duration: return best.longestHold > 0 ? "Your best: \(SetFormat.clock(best.longestHold))" : nil
        case .bodyweightReps: return best.mostReps > 0 ? "Your best: \(best.mostReps) reps" : nil
        case .weightReps: return best.heaviest > 0 ? "Your heaviest: \(best.heaviest.kg) kg" : nil
        }
    }

    private func defaultSet(for exercise: Exercise?) -> DraftSet {
        switch exercise?.metric ?? .weightReps {
        case .duration: DraftSet(weight: 0, reps: 0, durationSeconds: 30)
        case .bodyweightReps: DraftSet(weight: 0, reps: 10)
        case .weightReps: DraftSet(weight: exercise?.kind.barWeight ?? 20, reps: 5)
        }
    }

    private func prefill(for exercise: Exercise) -> DraftSet {
        if let last = Records.lastSets(for: exercise.id, in: store.history)?.first {
            return DraftSet(weight: last.weightKg ?? 0, reps: last.reps ?? 0, durationSeconds: last.durationSeconds)
        }
        return defaultSet(for: exercise)
    }

    private func save() async {
        guard let exercise else { return }
        let total = sets.reduce(0) { $0 + ($1.durationSeconds ?? 60) }
        var draft = WorkoutDraft(name: exercise.name, startedAt: date,
                                 endedAt: date.addingTimeInterval(TimeInterval(max(60, total))))
        draft.exercises = [DraftExercise(exerciseRef: exercise.id, sets: sets.map {
            var set = $0
            set.completedAt = date
            return set
        })]
        await store.logManual(draft)
        dismiss()
    }
}

/// Editor for one set in the exercise's own terms. Shared by quick log and the session editor.
struct QuickSetRow: View {
    @Binding var set: DraftSet
    let metric: ExerciseMetric

    var body: some View {
        switch metric {
        case .duration:
            HStack {
                Stepper(value: seconds, in: 0...3600, step: 5) {
                    Text(SetFormat.clock(set.durationSeconds ?? 0)).font(.cast(.title3)).monospacedDigit()
                }
            }
            weightField(label: "Added kg")
        case .bodyweightReps:
            Stepper(value: $set.reps, in: 0...500) {
                Text("\(set.reps) reps").font(.cast(.title3))
            }
            weightField(label: "Added kg")
        case .weightReps:
            HStack(spacing: 12) {
                TextField("kg", value: $set.weight, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .font(.cast(.headline))
                    .frame(width: 80)
                Text("kg ×").foregroundStyle(Palette.slateText)
                Stepper(value: $set.reps, in: 0...100) {
                    Text("\(set.reps)").font(.cast(.headline))
                }
            }
        }
    }

    private var seconds: Binding<Int> {
        Binding(get: { set.durationSeconds ?? 0 }, set: { set.durationSeconds = $0 })
    }

    private func weightField(label: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.slateText)
            Spacer()
            TextField("0", value: $set.weight, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
        .font(.subheadline)
    }
}
