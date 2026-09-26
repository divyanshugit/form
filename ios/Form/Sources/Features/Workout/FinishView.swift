import SwiftUI

/// End of session: a name, one or two takeaways, save. (The progress photo arrives in the photo phase.)
struct FinishView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: ActiveWorkout
    let onDone: () -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var saved: WorkoutDraft?
    @State private var records: [PersonalRecord] = []
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let saved {
                        savedState(saved)
                    } else {
                        summary
                    }
                }
                .padding(20)
            }
            .background(Palette.bone)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Keep going") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            name = workout.draft.name
            records = store.records(for: workout.draft)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Session \(store.history.count + 1)").labelStyle()
            TextField("Name", text: $name)
                .font(.cast(.title))
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)

            HStack(spacing: 24) {
                stat(ActiveWorkoutView.elapsed(from: workout.draft.startedAt, to: .now), "time")
                stat("\(workout.draft.completedSets.count)", "sets")
                stat(Int(workout.draft.volume).formatted(), "kg moved")
            }

            takeaways

            Button {
                Task { await save() }
            } label: {
                if isSaving { ProgressView() } else { Text("Save session") }
            }
            .buttonStyle(PrimaryKeyStyle(height: 72))
            .disabled(isSaving)
        }
    }

    @ViewBuilder
    private var takeaways: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Takeaways").labelStyle()
            if records.isEmpty {
                Text(workout.draft.completedSets.count >= 12 ? "A full session in the bank." : "Showed up. That's the whole game.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            } else {
                ForEach(records.prefix(2)) { record in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.orange).frame(width: 6, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("New PR · \(store.library.exercise(record.exerciseRef)?.name ?? record.exerciseRef)")
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Text(recordLine(record))
                                .foregroundStyle(Palette.slateText)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func savedState(_ draft: WorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Saved.").font(.cast(56)).foregroundStyle(Palette.ink)
            Text(store.pendingCount > 0
                 ? "Stored on your phone. It'll sync as soon as you have signal."
                 : "In the log. See you next session.")
                .foregroundStyle(Palette.slateText)
            Button {
                showingCamera = true
            } label: {
                Label("Progress photo", systemImage: "camera.fill")
            }
            .buttonStyle(PrimaryKeyStyle(height: 68))
            Text("Same spot, same pose. Your last photo shows as a ghost to line up with.")
                .font(.footnote)
                .foregroundStyle(Palette.slateText)
            Button("Done") { onDone() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .tint(Palette.denim)
        }
        .padding(.top, 40)
        .fullScreenCover(isPresented: $showingCamera, onDismiss: onDone) {
            CameraView(workoutID: draft.id)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.cast(.title2)).foregroundStyle(Palette.ink)
            Text(label).labelStyle()
        }
    }

    private func recordLine(_ record: PersonalRecord) -> String {
        switch record.kind {
        case .estimatedOneRepMax:
            let before = record.previousBest.map { " (was \(Int($0.rounded())))" } ?? ""
            return "\(record.weight.kg) × \(record.reps) · est. 1RM \(Int(record.estimatedOneRepMax.rounded())) kg\(before)"
        case .heaviest:
            return "Heaviest yet: \(record.weight.kg) kg × \(record.reps)"
        case .mostReps:
            let before = record.previousBest.map { " (was \(Int($0)))" } ?? ""
            return "\(record.reps) reps\(record.weight > 0 ? " with +\(record.weight.kg) kg" : "")\(before)"
        case .longestHold:
            let before = record.previousBest.map { " (was \(SetFormat.clock(Int($0))))" } ?? ""
            return "Held \(SetFormat.clock(record.durationSeconds ?? 0))\(before)"
        }
    }

    private func save() async {
        isSaving = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { workout.rename(trimmed) }
        saved = await store.finishActive()
        isSaving = false
        if saved == nil { onDone() }
    }
}
