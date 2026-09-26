import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var store
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @State private var muscle: String?

    private var results: [Exercise] {
        let found = store.library.search(query, muscle: muscle)
        // Exercises you've done before float to the top.
        let done = Set(store.history.flatMap { $0.sortedExercises.map(\.exerciseRef) })
        return found.sorted { (done.contains($0.id) ? 0 : 1, $0.name) < (done.contains($1.id) ? 0 : 1, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip("All", selected: muscle == nil) { muscle = nil }
                            ForEach(store.library.muscles, id: \.self) { m in
                                chip(m.capitalized, selected: muscle == m) { muscle = m }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(results) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).foregroundStyle(Palette.ink)
                                    Text([exercise.primaryMuscle, exercise.equipment?.capitalized]
                                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(Palette.slateText)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Palette.orange)
                            }
                            .frame(minHeight: 44)
                        }
                        .listRowBackground(Palette.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bone)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bench, squat, curl…")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Palette.chalk : Palette.ink)
                .background(selected ? Palette.denimFixed : Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
