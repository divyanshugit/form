import SwiftUI

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var store
    @Environment(CustomExerciseStore.self) private var custom
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @State private var muscle: String?
    @State private var showingNew = false
    @State private var info: Exercise?

    private var results: [Exercise] {
        _ = custom.rows.count // re-run when your exercises change
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
                if results.isEmpty || !query.isEmpty {
                    Section {
                        Button {
                            showingNew = true
                        } label: {
                            Label(query.isEmpty ? "Create an exercise" : "Create \u{201C}\(query)\u{201D}",
                                  systemImage: "plus.square.dashed")
                                .font(.headline)
                                .frame(minHeight: 44)
                        }
                        .listRowBackground(Palette.card)
                    }
                }
                Section {
                    ForEach(results) { exercise in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(exercise.name).font(.headline).foregroundStyle(Palette.ink)
                                        if exercise.isCustom {
                                            Text("YOURS")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .foregroundStyle(Palette.inkFixed)
                                                .background(Palette.orange, in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    Text(exercise.summary)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.slateText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Adds this exercise to the session")

                            Button {
                                info = exercise
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                                    .foregroundStyle(Palette.denim)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("About \(exercise.name)")
                        }
                        .padding(.vertical, 4)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("New") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewExerciseView(prefilledName: query) { created in
                    onPick(created)
                    dismiss()
                }
            }
            .sheet(item: $info) { ExerciseInfoView(exercise: $0) }
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
