import SwiftUI

/// Search the whole library from the Body tab; tap for details, or add straight to a workout.
struct ExerciseSearchView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var showingWorkout: Bool

    @State private var query = ""
    @State private var info: Exercise?

    var body: some View {
        NavigationStack {
            List(store.library.search(query)) { exercise in
                Button { info = exercise } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.headline).foregroundStyle(Palette.ink)
                        Text([exercise.bodyPart?.title, exercise.equipment?.capitalized].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                    }
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $info) { exercise in
                ExerciseInfoView(exercise: exercise, onAdd: {
                    if store.active == nil { store.startWorkout() }
                    store.active?.addExercise(exercise)
                    info = nil
                    dismiss()
                    showingWorkout = true
                })
            }
        }
    }
}
