import SwiftUI

/// Create or edit one of your own exercises: name, what a set records, equipment, muscle, and a short description.
struct NewExerciseView: View {
    @Environment(CustomExerciseStore.self) private var custom
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var editing: CustomExerciseRow? = nil
    var prefilledName: String = ""
    var onSave: ((Exercise) -> Void)? = nil

    @State private var name = ""
    @State private var metric: ExerciseMetric = .weightReps
    @State private var equipment = "barbell"
    @State private var muscle = "chest"
    @State private var about = ""
    @State private var isSaving = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Landmine press", text: $name)
                        .font(.headline)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Picker("Each set records", selection: $metric) {
                        Text("Weight × reps").tag(ExerciseMetric.weightReps)
                        Text("Bodyweight reps").tag(ExerciseMetric.bodyweightReps)
                        Text("Hold time").tag(ExerciseMetric.duration)
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(CustomExerciseRow.equipmentChoices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Main muscle", selection: $muscle) {
                        ForEach(store.library.muscles, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                } footer: {
                    Text(metricHint)
                }

                Section {
                    TextField("What is it, what does it work, how do you do it?", text: $about, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Two or three lines. It shows under the name when you pick exercises.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .navigationTitle(editing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var metricHint: String {
        switch metric {
        case .weightReps: "Logged with the loaded bar or weight steps, like a bench press."
        case .bodyweightReps: "Reps are the score, with optional added weight, like pull-ups."
        case .duration: "Timed with a stopwatch, like a dead hang or plank."
        }
    }

    private func load() {
        if let editing {
            name = editing.name
            metric = editing.metric
            equipment = editing.equipment ?? "other"
            muscle = editing.primaryMuscle ?? "chest"
            about = editing.description ?? ""
        } else {
            name = prefilledName
        }
    }

    private func save() async {
        isSaving = true
        let row = CustomExerciseRow(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            equipment: equipment,
            primaryMuscle: muscle,
            metric: metric,
            description: about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : about
        )
        let exercise = await custom.save(row)
        isSaving = false
        onSave?(exercise)
        dismiss()
    }
}
