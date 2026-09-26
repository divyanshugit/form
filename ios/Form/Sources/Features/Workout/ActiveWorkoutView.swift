import SwiftUI

/// One job: log the current set. The weight is huge, the bar shows the plates, the key is chunky.
struct ActiveWorkoutView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: ActiveWorkout

    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if workout.draft.exercises.isEmpty {
                        emptyState
                    } else if let exercise = workout.focusedExercise, let set = workout.focusedSet, let focus = workout.focus {
                        currentSet(exercise: exercise, set: set, focus: focus)
                    } else {
                        allDone
                    }
                    upNext
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.denim)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.bone)
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                workout.addExercise(exercise)
            }
        }
        .sheet(isPresented: $showingFinish) {
            FinishView(workout: workout) {
                showingFinish = false
                dismiss()
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) {
                store.discardActive()
                dismiss()
            }
        } message: {
            Text("Nothing has been logged yet.")
        }
        .sensoryFeedback(.success, trigger: workout.draft.completedSets.count)
        .sensoryFeedback(.warning, trigger: workout.restFinishedCount)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 48, height: 48)
                    .background(Palette.card, in: Circle())
            }
            .accessibilityLabel("Minimise workout")

            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.orange).frame(width: 6, height: 16)
                    Text(Self.elapsed(from: workout.draft.startedAt, to: context.date))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                }
            }
            Spacer()

            Button("END") {
                if workout.draft.completedSets.isEmpty {
                    confirmDiscard = true
                } else {
                    showingFinish = true
                }
            }
            .buttonStyle(InkPillStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: Current set

    @ViewBuilder
    private func currentSet(exercise: DraftExercise, set: DraftSet, focus: ActiveWorkout.SetFocus) -> some View {
        let info = workout.exercise(for: exercise.exerciseRef)
        let kind = info?.kind ?? .other
        let previous = workout.previous(for: exercise.exerciseRef)
        let previousSet = previous.flatMap { $0.indices.contains(focus.set) ? $0[focus.set] : $0.last }

        VStack(alignment: .leading, spacing: 4) {
            Text("\(String(format: "%02d", focus.exercise + 1)) / \(String(format: "%02d", workout.draft.exercises.count)) · \(info?.primaryMuscle ?? "")")
                .labelStyle()
            Text(info?.name ?? exercise.exerciseRef)
                .font(.title.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }

        let metric = info?.metric ?? .weightReps

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Set \(focus.set + 1) of \(exercise.sets.count)\(set.kind == .warmup ? " · warm-up" : "")")
                    .labelStyle(Palette.ink)
                Spacer()
                if let previousSet {
                    Text("Last \(SetFormat.describe(previousSet, metric: metric))").labelStyle()
                }
            }

            switch metric {
            case .weightReps:
                weightPanel(set: set, kind: kind)
            case .bodyweightReps:
                bodyweightPanel(set: set)
            case .duration:
                holdPanel(set: set)
            }
        }
        .padding(18)
        .card(Palette.fog)

        switch metric {
        case .weightReps:
            repsCard(set: set, previousReps: previousSet?.reps)
        case .bodyweightReps, .duration:
            addedWeightCard(set: set)
        }

        restOrDoneKey
    }

    // MARK: Panels per metric

    @ViewBuilder
    private func weightPanel(set: DraftSet, kind: EquipmentKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(set.weight.kg)
                .font(.cast(88))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText(value: set.weight))
                .animation(.snappy, value: set.weight)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind == .dumbbell ? "KG EACH" : "KG").labelStyle(Palette.ink)
                Text("×\(set.reps)")
                    .font(.cast(.title))
                    .foregroundStyle(Palette.denim)
                    .contentTransition(.numericText(value: Double(set.reps)))
            }
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .combine)

        if let bar = kind.barWeight {
            LoadedBarView(weight: set.weight, bar: bar)
            PlateReadout(weight: set.weight, bar: bar)
        } else if kind == .dumbbell {
            DumbbellPairView(weight: set.weight)
                .frame(maxWidth: .infinity)
        }

        HStack(spacing: 10) {
            stepKey(-kind.steps.large)
            stepKey(-kind.steps.small)
            stepKey(kind.steps.small)
            stepKey(kind.steps.large)
        }
    }

    /// Pull-ups, push-ups, dips: the reps are the score.
    @ViewBuilder
    private func bodyweightPanel(set: DraftSet) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(set.reps)")
                .font(.cast(96))
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(set.reps)))
                .animation(.snappy, value: set.reps)
            VStack(alignment: .leading, spacing: 0) {
                Text("REPS").labelStyle(Palette.ink)
                Text(set.weight > 0 ? "+\(set.weight.kg) kg" : "bodyweight")
                    .font(.headline)
                    .foregroundStyle(Palette.denim)
            }
        }
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .combine)

        HStack(spacing: 10) {
            ForEach([-5, -1, 1, 5], id: \.self) { delta in
                Button(delta > 0 ? "+\(delta)" : "−\(abs(delta))") { workout.adjustReps(by: delta) }
                    .buttonStyle(StepKeyStyle())
                    .accessibilityLabel(delta > 0 ? "Add \(delta) reps" : "Remove \(abs(delta)) reps")
            }
        }
        .sensoryFeedback(.selection, trigger: workout.focusedSet?.reps)
    }

    /// Dead hang, plank, L-sit: a stopwatch, or type the time in with the steps.
    @ViewBuilder
    private func holdPanel(set: DraftSet) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let running = workout.holdElapsed(at: context.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SetFormat.clock(running ?? set.durationSeconds ?? 0))
                        .font(.cast(96))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(running != nil ? Palette.orange : Palette.ink)
                        .contentTransition(.numericText())
                    Text(running != nil ? "HOLDING" : "HOLD").labelStyle(Palette.ink)
                }
                Button {
                    workout.toggleHold()
                } label: {
                    Label(running != nil ? "Stop" : "Start hold",
                          systemImage: running != nil ? "stop.fill" : "timer")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Palette.chalk)
                        .background(Palette.navy, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .heavy), trigger: running == nil)
                .accessibilityHint("Starts a stopwatch; tap again to save the time")

                HStack(spacing: 10) {
                    ForEach([-15, -5, 5, 15], id: \.self) { delta in
                        Button(delta > 0 ? "+\(delta)s" : "−\(abs(delta))s") { workout.adjustDuration(by: delta) }
                            .buttonStyle(StepKeyStyle())
                            .disabled(running != nil)
                            .accessibilityLabel(delta > 0 ? "Add \(delta) seconds" : "Remove \(abs(delta)) seconds")
                    }
                }
            }
        }
    }

    /// Optional load for weighted pull-ups, dips or a weighted hang.
    private func addedWeightCard(set: DraftSet) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Added weight").labelStyle(Palette.ink)
                Text(set.weight > 0 ? "belt or vest" : "none").labelStyle()
            }
            Spacer()
            Button { workout.adjustWeight(by: -2.5) } label: { Image(systemName: "minus").frame(width: 56) }
                .buttonStyle(StepKeyStyle())
                .frame(width: 72)
                .accessibilityLabel("Remove 2.5 kilograms")
            Text(set.weight.kg)
                .font(.cast(32))
                .frame(minWidth: 64)
            Button { workout.adjustWeight(by: 2.5) } label: { Image(systemName: "plus").frame(width: 56) }
                .buttonStyle(StepKeyStyle())
                .frame(width: 72)
                .accessibilityLabel("Add 2.5 kilograms")
        }
        .padding(16)
        .card()
    }

    private func stepKey(_ delta: Double) -> some View {
        Button(delta > 0 ? "+\(delta.kg)" : "−\(abs(delta).kg)") {
            workout.adjustWeight(by: delta)
        }
        .buttonStyle(StepKeyStyle())
        .sensoryFeedback(.selection, trigger: workout.focusedSet?.weight)
        .accessibilityLabel(delta > 0 ? "Add \(delta.kg) kilograms" : "Remove \(abs(delta).kg) kilograms")
    }

    private func repsCard(set: DraftSet, previousReps: Int?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reps").labelStyle(Palette.ink)
                if let previousReps { Text("Last \(previousReps)").labelStyle() }
            }
            Spacer()
            Button { workout.adjustReps(by: -1) } label: {
                Image(systemName: "minus").frame(width: 56)
            }
            .buttonStyle(StepKeyStyle())
            .frame(width: 72)
            .accessibilityLabel("One fewer rep")

            Text("\(set.reps)")
                .font(.cast(40))
                .monospacedDigit()
                .frame(minWidth: 64)
                .contentTransition(.numericText(value: Double(set.reps)))

            Button { workout.adjustReps(by: 1) } label: {
                Image(systemName: "plus").frame(width: 56)
            }
            .buttonStyle(StepKeyStyle())
            .frame(width: 72)
            .accessibilityLabel("One more rep")
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private var restOrDoneKey: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = workout.restRemaining(at: context.date)
            if remaining > 0 {
                RestBanner(remaining: remaining, total: workout.restTotal,
                           minus: { workout.adjustRest(by: -15) },
                           plus: { workout.adjustRest(by: 15) },
                           skip: { workout.skipRest() })
            } else {
                Button {
                    workout.completeFocusedSet()
                } label: {
                    Label("Set done", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryKeyStyle(height: 72))
            }
        }
    }

    // MARK: Up next

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !workout.draft.exercises.isEmpty {
                Text("The session").labelStyle().padding(.bottom, 8).padding(.top, 8)
            }
            ForEach(Array(workout.draft.exercises.enumerated()), id: \.element.id) { exerciseIndex, exercise in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(workout.exercise(for: exercise.exerciseRef)?.name ?? exercise.exerciseRef)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Menu {
                            Button("Add set", systemImage: "plus") { workout.addSet(toExercise: exerciseIndex) }
                            Button("Remove exercise", systemImage: "trash", role: .destructive) {
                                workout.removeExercise(at: exerciseIndex)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 44, height: 44)
                                .foregroundStyle(Palette.slateText)
                        }
                        .accessibilityLabel("Options for this exercise")
                    }
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                        let target = ActiveWorkout.SetFocus(exercise: exerciseIndex, set: setIndex)
                        Button {
                            if set.isDone { workout.undoSet(target) } else { workout.select(target) }
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(set.isDone ? Palette.denim : (workout.focus == target ? Palette.orange : Palette.rule))
                                    .frame(width: 4, height: 22)
                                Text(set.kind == .warmup ? "Warm-up" : "Set \(setIndex + 1)")
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text(SetFormat.describe(set, metric: workout.exercise(for: exercise.exerciseRef)?.metric ?? .weightReps))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(set.isDone ? Palette.slateText : Palette.ink)
                                if set.isDone {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.denim)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(set.isDone ? "Undo this set" : "Make this the current set")
                    }
                }
                .padding(.vertical, 6)
                Divider().overlay(Palette.rule)
            }
        }
    }

    // MARK: States

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Empty bar.").font(.cast(.largeTitle)).foregroundStyle(Palette.ink)
            Text("Add your first exercise. Last time's weights load automatically.")
                .foregroundStyle(Palette.slateText)
            Button {
                showingPicker = true
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .buttonStyle(PrimaryKeyStyle())
            .padding(.top, 8)
        }
        .padding(.top, 24)
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Done.").font(.cast(56)).foregroundStyle(Palette.ink)
            Text("Every set is logged. Add more, or finish and take today's photo.")
                .foregroundStyle(Palette.slateText)
            Button("Finish") { showingFinish = true }
                .buttonStyle(PrimaryKeyStyle(height: 72))
        }
        .padding(.top, 16)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Rest countdown that takes the key's place: draining bar, ±15, skip.
struct RestBanner: View {
    let remaining: TimeInterval
    let total: TimeInterval
    let minus: () -> Void
    let plus: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rest · load up").labelStyle(Palette.chalk.opacity(0.8))
                Spacer()
                Text(Self.format(remaining))
                    .font(.cast(40))
                    .monospacedDigit()
                    .foregroundStyle(Palette.chalk)
                    .contentTransition(.numericText(countsDown: true))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.chalk.opacity(0.15))
                    Capsule().fill(Palette.orange)
                        .frame(width: geo.size.width * (total > 0 ? remaining / total : 0))
                        .animation(.linear(duration: 1), value: remaining)
                }
            }
            .frame(height: 6)
            HStack(spacing: 10) {
                Button("−15", action: minus).buttonStyle(RestKeyStyle())
                Button("+15", action: plus).buttonStyle(RestKeyStyle())
                Button("Skip rest", action: skip).buttonStyle(RestKeyStyle(filled: true))
            }
        }
        .padding(18)
        .background(Palette.navy, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resting, \(Int(remaining)) seconds left")
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct RestKeyStyle: ButtonStyle {
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .monospaced).weight(.bold))
            .foregroundStyle(filled ? Palette.inkFixed : Palette.chalk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(filled ? Palette.orange : Palette.chalk.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
