import SwiftUI

/// Everything for one body part: exercises you've done (last set, best), then the rest of the library.
struct BodyPartHubView: View {
    @Environment(WorkoutStore.self) private var store
    let part: BodyPart
    @Binding var showingWorkout: Bool

    @State private var filter: String?
    @State private var info: Exercise?
    @State private var showAllExplore = false

    private static let exploreLimit = 8

    private var exercises: [Exercise] {
        store.library.all.filter { exercise in
            guard exercise.bodyPart == part else { return false }
            guard let filter else { return true }
            return chipsAreMuscles
                ? exercise.primaryMuscles.first?.lowercased() == filter
                : exercise.equipment?.lowercased() == filter
        }
    }

    /// Muscle chips when the part has several muscles; otherwise equipment chips.
    private var chipsAreMuscles: Bool { part.muscles.count > 1 }

    private var chips: [(value: String, label: String)] {
        if chipsAreMuscles {
            return part.muscles
                .filter { m in store.library.all.contains { $0.primaryMuscles.first?.lowercased() == m } }
                .map { ($0, $0.capitalized) }
        }
        var seen = Set<String>()
        return store.library.all
            .filter { $0.bodyPart == part }
            .compactMap { $0.equipment?.lowercased() }
            .filter { seen.insert($0).inserted }
            .sorted()
            .map { ($0, $0.capitalized) }
    }

    var body: some View {
        let stats = BodyStats.compute(history: store.history, library: store.library)[part] ?? BodyPartStats()
        let lastDone = BodyStats.lastDone(history: store.history)
        let all = exercises
        let mine = all.filter { lastDone[$0.id] != nil }
            .sorted { (lastDone[$0.id] ?? .distantPast) > (lastDone[$1.id] ?? .distantPast) }
        let explore = all.filter { lastDone[$0.id] == nil }
        let shownExplore = showAllExplore ? explore : Array(explore.prefix(Self.exploreLimit))

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(part.title.uppercased()).font(.cast(34)).foregroundStyle(Palette.ink)
                        Text(subtitle(stats))
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                    }
                    Spacer()
                    MuscleMapView(side: part.prefersBackView ? .back : .front,
                                  freshness: [part: .fresh])
                        .frame(height: 88)
                }

                if chips.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip("All", selected: filter == nil) { filter = nil }
                            ForEach(chips, id: \.value) { c in
                                chip(c.label, selected: filter == c.value) { filter = c.value }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                section("Your \(part.title.lowercased()) · \(mine.count)") {
                    if mine.isEmpty {
                        Text("Nothing logged here yet. Pick something below to get started.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(mine) { exercise in
                            Button { info = exercise } label: { mineRow(exercise, lastDone: lastDone[exercise.id]) }
                                .buttonStyle(.plain)
                            if exercise.id != mine.last?.id { Divider().overlay(Palette.rule) }
                        }
                    }
                }

                if !explore.isEmpty {
                    section("Explore · \(explore.count)") {
                        ForEach(shownExplore) { exercise in
                            exploreRow(exercise)
                            if exercise.id != shownExplore.last?.id { Divider().overlay(Palette.rule) }
                        }
                    }
                    if explore.count > Self.exploreLimit {
                        Button(showAllExplore ? "Show fewer" : "Show all \(explore.count)") {
                            withAnimation { showAllExplore.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.denim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.bone)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $info) { exercise in
            ExerciseInfoView(exercise: exercise, onAdd: { add(exercise) })
        }
    }

    private func subtitle(_ stats: BodyPartStats) -> String {
        guard stats.lastTrained != nil else { return "Not trained yet" }
        return "Trained \(BodyStats.ago(stats.daysSince)) · \(stats.recentSets) sets in 7 days"
    }

    private func add(_ exercise: Exercise) {
        if store.active == nil { store.startWorkout() }
        store.active?.addExercise(exercise)
        info = nil
        showingWorkout = true
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Palette.chalk : Palette.ink)
                .background(selected ? Palette.ink : Palette.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: selected ? 0 : 1))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).labelStyle()
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 16)
                .card()
        }
    }

    private func mineRow(_ exercise: Exercise, lastDone: Date?) -> some View {
        let last = Records.lastSets(for: exercise.id, in: store.history)?.first
        let best = store.bests[exercise.id]
        let days = lastDone.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: $0), to: Calendar.current.startOfDay(for: .now)).day ?? 0 }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                Text([exercise.equipment?.capitalized, BodyStats.ago(days)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Palette.slateText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let last {
                    Text(SetFormat.describe(last, metric: exercise.metric))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Palette.ink)
                }
                if let best, let label = bestLabel(best, metric: exercise.metric) {
                    Text("BEST \(label)")
                        .font(.label)
                        .foregroundStyle(Palette.inkFixed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.orange, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.slateText)
        }
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private func bestLabel(_ best: Records.Best, metric: ExerciseMetric) -> String? {
        switch metric {
        case .weightReps: best.heaviest > 0 ? "\(best.heaviest.kg) KG" : nil
        case .bodyweightReps: best.mostReps > 0 ? "\(best.mostReps) REPS" : nil
        case .duration: best.longestHold > 0 ? SetFormat.clock(best.longestHold) : nil
        }
    }

    private func exploreRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            Button { info = exercise } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                        if let equipment = exercise.equipment {
                            Text(equipment.capitalized).font(.subheadline).foregroundStyle(Palette.slateText)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { add(exercise) } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.bone, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.rule, lineWidth: 1))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add \(exercise.name) to workout")
        }
        .frame(minHeight: 56)
    }
}
