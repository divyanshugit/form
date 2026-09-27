import SwiftUI

/// Define what a session was after the fact: rename it, add notes, and log exercises and sets.
/// Works for Form sessions and WHOOP imports alike; WHOOP strain and heart rate are kept.
struct EditWorkoutView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: WorkoutRow

    @State private var name = ""
    @State private var notes = ""
    @State private var exercises: [DraftExercise] = []
    @State private var showingPicker = false
    @State private var scanning = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.headline)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text(workout.startedAt.formatted(date: .complete, time: .shortened))
                }

                if workout.strain != nil {
                    Section("From WHOOP") {
                        HeartRateStrip(workout: workout)
                            .listRowInsets(EdgeInsets())
                    }
                }

                ForEach($exercises) { $exercise in
                    Section {
                        ForEach($exercise.sets) { $set in
                            QuickSetRow(set: $set, metric: store.library.metric(exercise.exerciseRef))
                        }
                        .onDelete { exercise.sets.remove(atOffsets: $0) }
                        Button("Add set", systemImage: "plus") {
                            let last = exercise.sets.last
                            exercise.sets.append(DraftSet(weight: last?.weight ?? 20, reps: last?.reps ?? 8,
                                                          completedAt: workout.startedAt, durationSeconds: last?.durationSeconds))
                        }
                    } header: {
                        HStack {
                            Text(store.library.exercise(exercise.exerciseRef)?.name ?? exercise.exerciseRef)
                            Spacer()
                            Button(role: .destructive) {
                                exercises.removeAll { $0.id == exercise.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Remove exercise")
                        }
                    }
                }

                Section {
                    Button("Add exercise", systemImage: "plus.circle.fill") { showingPicker = true }
                    Button("Scan a workout board", systemImage: "text.viewfinder") { scanning = true }
                } footer: {
                    if exercises.isEmpty {
                        Text("Snap the whiteboard from your class and Form fills in the exercises.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle(workout.isWhoopImport ? "Define session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    exercises.append(draftExercise(for: exercise))
                }
            }
            .sheet(isPresented: $scanning) {
                ScanBoardView(confirmTitle: { "Add \($0) exercise\($0 == 1 ? "" : "s")" }) { title, scanned in
                    // A WHOOP import is named after the sport ("Functional Fitness"); prefer the board's title.
                    if !title.isEmpty, name == workout.name { name = title }
                    for item in scanned {
                        exercises.append(draftExercise(for: item.exercise, sets: item.sets, reps: item.reps,
                                                       seconds: item.seconds, note: item.note))
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Sets for a newly added exercise: last time's weights, the planned target when given,
    /// all logged at the session's start (this session already happened).
    private func draftExercise(for exercise: Exercise, sets setCount: Int? = nil, reps: Int? = nil,
                               seconds: Int? = nil, note: String? = nil) -> DraftExercise {
        let previous = Records.lastSets(for: exercise.id, in: store.history)
        var sets = previous?.map {
            DraftSet(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0, completedAt: workout.startedAt, durationSeconds: $0.durationSeconds)
        } ?? (0..<3).map { _ in
            switch exercise.metric {
            case .duration: DraftSet(weight: 0, reps: 0, completedAt: workout.startedAt, durationSeconds: 30)
            case .bodyweightReps: DraftSet(weight: 0, reps: 8, completedAt: workout.startedAt)
            case .weightReps: DraftSet(weight: exercise.kind.barWeight ?? 10, reps: 8, completedAt: workout.startedAt)
            }
        }
        if let setCount, setCount > 0 {
            let template = sets.last ?? DraftSet(weight: 0, reps: 8, completedAt: workout.startedAt)
            if sets.count > setCount { sets.removeLast(sets.count - setCount) }
            while sets.count < setCount {
                sets.append(DraftSet(weight: template.weight, reps: template.reps, completedAt: workout.startedAt,
                                     durationSeconds: template.durationSeconds))
            }
        }
        for i in sets.indices {
            if let reps, exercise.metric != .duration { sets[i].reps = reps }
            if let seconds, exercise.metric == .duration { sets[i].durationSeconds = seconds }
        }
        return DraftExercise(exerciseRef: exercise.id, sets: sets, notes: note)
    }

    private func load() {
        name = workout.name
        notes = workout.notes ?? ""
        exercises = workout.sortedExercises.map { row in
            DraftExercise(id: row.id, exerciseRef: row.exerciseRef, sets: row.sortedSets.map { set in
                DraftSet(id: set.id, kind: set.kind, weight: set.weightKg ?? 0, reps: set.reps ?? 0,
                         completedAt: set.completedAt ?? workout.startedAt, durationSeconds: set.durationSeconds)
            }, notes: row.notes)
        }
    }

    private func save() async {
        isSaving = true
        var draft = WorkoutDraft(id: workout.id, name: name.trimmingCharacters(in: .whitespaces),
                                 startedAt: workout.startedAt, endedAt: workout.endedAt)
        draft.notes = notes.isEmpty ? nil : notes
        draft.exercises = exercises.filter { !$0.sets.isEmpty }
        await store.update(draft, keeping: workout)
        isSaving = false
        dismiss()
    }
}
