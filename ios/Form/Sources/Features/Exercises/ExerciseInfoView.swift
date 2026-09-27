import Charts
import SwiftUI

/// One exercise: your numbers and progress chart first, then what it is and how to do it.
/// Works for every metric: est. 1RM for lifts, reps for bodyweight, hold time for planks and hangs.
struct ExerciseInfoView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(CustomExerciseStore.self) private var custom
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    /// Shows an "Add to workout" button when set (e.g. from the Body tab, not mid-workout).
    var onAdd: (() -> Void)? = nil

    @State private var editing: CustomExerciseRow?
    @State private var confirmDelete = false
    /// nil = pick automatically (3M if it has enough points, else All).
    @State private var range: ChartRange?

    private var current: Exercise { store.library.exercise(exercise.id) ?? exercise }

    enum ChartRange: String, CaseIterable, Identifiable {
        case month = "1M", quarter = "3M", year = "1Y", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .month: 31
            case .quarter: 92
            case .year: 366
            case .all: nil
            }
        }
    }

    var body: some View {
        let history = Records.history(for: current.id, in: store.history)
        let trend = store.trend(for: current.id, metric: current.metric)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(metricLabel).labelStyle()
                        Text(current.name.uppercased())
                            .font(.cast(28))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        muscles
                    }

                    if history.sessions == 0 {
                        Text("No sessions yet. Log this once and your chart and records start here.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .card()
                    } else {
                        statTiles(history)
                        progress(trend)
                        records(history)
                        lastSession(history)
                    }

                    if let onAdd {
                        Button(action: onAdd) {
                            Label("Add to workout", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(Palette.inkFixed)
                                .background(Palette.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    about
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

    // MARK: Header

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
                HStack(spacing: 6) {
                    ForEach(all, id: \.0) { name, primary in
                        Text(name.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .foregroundStyle(primary ? Palette.inkFixed : Palette.denim)
                            .background(primary ? Palette.orange : Palette.fog, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Numbers

    private func statTiles(_ h: Records.ExerciseHistory) -> some View {
        let tiles: [(String, String, String)] = switch current.metric {
        case .weightReps:
            [("Heaviest", h.heaviest.map { $0.value.kg } ?? "–", "kg"),
             ("Est. 1RM", h.bestOneRepMax.map { "\(Int($0.value.rounded()))" } ?? "–", "kg"),
             ("Sessions", "\(h.sessions)", "")]
        case .bodyweightReps:
            [("Most reps", h.mostReps.map { "\(Int($0.value))" } ?? "–", ""),
             ("Last best", lastBest(h).map { "\(Int($0))" } ?? "–", "reps"),
             ("Sessions", "\(h.sessions)", "")]
        case .duration:
            [("Longest", h.longestHold.map { SetFormat.clock(Int($0.value)) } ?? "–", ""),
             ("Last best", lastBest(h).map { SetFormat.clock(Int($0)) } ?? "–", ""),
             ("Sessions", "\(h.sessions)", "")]
        }
        return HStack(spacing: 8) {
            ForEach(tiles, id: \.0) { label, value, unit in
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).labelStyle()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value).font(.title3.monospaced().weight(.semibold)).foregroundStyle(Palette.ink)
                        if !unit.isEmpty { Text(unit).font(.caption.monospaced()).foregroundStyle(Palette.slateText) }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Best effort in the most recent session, in the metric's unit.
    private func lastBest(_ h: Records.ExerciseHistory) -> Double? {
        guard let sets = h.lastSession?.sets else { return nil }
        return switch current.metric {
        case .duration: sets.map { Double($0.durationSeconds ?? 0) }.max()
        case .bodyweightReps: sets.map { Double($0.reps ?? 0) }.max()
        case .weightReps: sets.map { PlateMath.estimatedOneRepMax(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }.max()
        }
    }

    // MARK: Chart

    private var trendTitle: String {
        switch current.metric {
        case .weightReps: "Est. 1RM"
        case .bodyweightReps: "Reps"
        case .duration: "Hold time"
        }
    }

    private func format(_ value: Double) -> String {
        switch current.metric {
        case .weightReps: "\(value.kg) kg"
        case .bodyweightReps: "\(Int(value)) reps"
        case .duration: SetFormat.clock(Int(value))
        }
    }

    private func points(_ trend: [(date: Date, value: Double)], in range: ChartRange) -> [(date: Date, value: Double)] {
        guard let days = range.days, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return trend }
        return trend.filter { $0.date >= cutoff }
    }

    private func effectiveRange(_ trend: [(date: Date, value: Double)]) -> ChartRange {
        if let range { return range }
        return points(trend, in: .quarter).count >= 2 ? .quarter : .all
    }

    @ViewBuilder
    private func progress(_ trend: [(date: Date, value: Double)]) -> some View {
        let selected = effectiveRange(trend)
        let shown = points(trend, in: selected)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trendTitle).labelStyle()
                Spacer()
                HStack(spacing: 2) {
                    ForEach(ChartRange.allCases) { r in
                        Button(r.rawValue) { range = r }
                            .font(.caption.monospaced())
                            .padding(.horizontal, 9)
                            .frame(minHeight: 28)
                            .foregroundStyle(r == selected ? Palette.chalk : Palette.slateText)
                            .background(r == selected ? Palette.ink : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityAddTraits(r == selected ? .isSelected : [])
                    }
                }
                .buttonStyle(.plain)
            }

            if shown.count >= 2, let first = shown.first, let last = shown.last {
                let delta = last.value - first.value
                Text(deltaText(delta))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(delta >= 0 ? Palette.denim : Palette.slateText)

                Chart(Array(shown.enumerated()), id: \.offset) { index, point in
                    LineMark(x: .value("Date", point.date), y: .value(trendTitle, point.value))
                        .foregroundStyle(Palette.denim)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value(trendTitle, point.value))
                        .foregroundStyle(index == shown.count - 1 ? Palette.orange : Palette.denim)
                        .symbolSize(index == shown.count - 1 ? 90 : 22)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Palette.rule)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(current.metric == .duration ? SetFormat.clock(Int(v)) : "\(Int(v))")
                                    .font(.caption2.monospaced())
                            }
                        }
                    }
                }
                .frame(height: 170)
                .accessibilityLabel("\(trendTitle) went from \(format(first.value)) to \(format(last.value)) over \(shown.count) sessions")
            } else {
                Text(trend.count >= 2
                     ? "Only one session in this range. Try a longer range."
                     : "Log one more session and your progress line starts here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.slateText)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            }
        }
        .padding(16)
        .card()
    }

    private func deltaText(_ delta: Double) -> String {
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : "±"
        let magnitude = abs(delta)
        let value = switch current.metric {
        case .weightReps: "\(magnitude.rounded().kg) kg"
        case .bodyweightReps: "\(Int(magnitude)) reps"
        case .duration: SetFormat.clock(Int(magnitude))
        }
        return "\(sign)\(value) in this range"
    }

    // MARK: Records

    @ViewBuilder
    private func records(_ h: Records.ExerciseHistory) -> some View {
        let rows: [(String, String, Date)] = {
            var rows: [(String, String, Date)] = []
            switch current.metric {
            case .weightReps:
                if let r = h.heaviest { rows.append(("Heaviest set", "\(r.value.kg) kg × \(r.set.reps ?? 0)", r.date)) }
                if let r = h.bestOneRepMax { rows.append(("Best est. 1RM", "\(Int(r.value.rounded())) kg", r.date)) }
                if let r = h.mostReps { rows.append(("Most reps", SetFormat.describe(r.set, metric: .weightReps), r.date)) }
            case .bodyweightReps:
                if let r = h.mostReps { rows.append(("Most reps", "\(Int(r.value)) reps", r.date)) }
                if let r = h.heaviest { rows.append(("Most added weight", "+\(r.value.kg) kg × \(r.set.reps ?? 0)", r.date)) }
            case .duration:
                if let r = h.longestHold { rows.append(("Longest hold", SetFormat.clock(Int(r.value)), r.date)) }
                if let r = h.heaviest { rows.append(("Most added weight", "+\(r.value.kg) kg", r.date)) }
            }
            return rows
        }()
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Records").labelStyle()
                VStack(spacing: 0) {
                    ForEach(rows, id: \.0) { label, value, date in
                        HStack {
                            Text(label).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(value).font(.subheadline.monospaced()).foregroundStyle(Palette.ink)
                            Text("· \(date.formatted(.dateTime.month(.abbreviated).day()))")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(Palette.denim)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        if label != rows.last?.0 { Divider().overlay(Palette.rule) }
                    }
                }
                .padding(.horizontal, 16)
                .card()
            }
        }
    }

    @ViewBuilder
    private func lastSession(_ h: Records.ExerciseHistory) -> some View {
        if let last = h.lastSession {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last session · \(last.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))").labelStyle()
                FlowRow(spacing: 6) {
                    ForEach(last.sets, id: \.id) { set in
                        Text(SetFormat.describe(set, metric: current.metric))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(Palette.fog, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: About

    @ViewBuilder
    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About").labelStyle()
            Text(current.summary)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

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
    }
}

/// Wraps children onto new lines when they run out of width.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
