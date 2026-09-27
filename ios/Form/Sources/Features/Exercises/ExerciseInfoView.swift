import SwiftUI

/// What an exercise is: description, muscles, how-to steps, demo image, and your own numbers.
struct ExerciseInfoView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(CustomExerciseStore.self) private var custom
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    @State private var editing: CustomExerciseRow?
    @State private var confirmDelete = false

    private var current: Exercise { store.library.exercise(exercise.id) ?? exercise }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metricLabel).labelStyle()
                        Text(current.name)
                            .font(.title.weight(.heavy))
                            .foregroundStyle(Palette.ink)
                        Text(current.summary)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let url = current.imageURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Palette.fog.frame(height: 180)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Demonstration of \(current.name)")
                    }

                    muscles

                    yourNumbers

                    if !current.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How to").labelStyle()
                            ForEach(Array(current.instructions.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.cast(.subheadline))
                                        .foregroundStyle(Palette.orange)
                                        .frame(width: 22, alignment: .leading)
                                    Text(step)
                                        .foregroundStyle(Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18)
                        .card()
                    }
                }
                .padding(20)
            }
            .background(Palette.bone)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let row = custom.row(for: current) {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Edit", systemImage: "pencil") { editing = row }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Exercise options")
                    }
                }
            }
            .sheet(item: $editing) { NewExerciseView(editing: $0) }
            .confirmationDialog("Delete \(current.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete exercise", role: .destructive) {
                    guard let row = custom.row(for: current) else { return }
                    Task {
                        await custom.delete(row.id)
                        dismiss()
                    }
                }
            } message: {
                Text("Sessions that used it keep their sets.")
            }
        }
    }

    private var metricLabel: String {
        let kind = switch current.metric {
        case .weightReps: "Weight × reps"
        case .bodyweightReps: "Bodyweight reps"
        case .duration: "Timed hold"
        }
        return [current.isCustom ? "Your exercise" : nil, kind, current.equipment?.capitalized]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var muscles: some View {
        let all = current.primaryMuscles.map { ($0, true) } + current.secondaryMuscles.map { ($0, false) }
        if !all.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(all, id: \.0) { name, primary in
                        Text(name.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .foregroundStyle(primary ? Palette.chalk : Palette.ink)
                            .background(primary ? Palette.denimFixed : Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: primary ? 0 : 1))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var yourNumbers: some View {
        let best = store.bests[current.id]
        let last = Records.lastSets(for: current.id, in: store.history)
        if best != nil || last != nil {
            HStack(spacing: 0) {
                if let best {
                    stat(bestValue(best), "your best")
                }
                if let last, let top = last.first {
                    stat(SetFormat.describe(top, metric: current.metric), "last time")
                }
            }
            .padding(.vertical, 12)
            .card()
        }
    }

    private func bestValue(_ best: Records.Best) -> String {
        switch current.metric {
        case .duration: SetFormat.clock(best.longestHold)
        case .bodyweightReps: "\(best.mostReps) reps"
        case .weightReps: "\(Int(best.oneRepMax.rounded())) kg 1RM"
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.cast(.headline)).foregroundStyle(Palette.ink)
            Text(label).labelStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
