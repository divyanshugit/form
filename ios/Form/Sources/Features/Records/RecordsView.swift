import Charts
import SwiftUI

/// The PR wall: bodyweight benchmarks up top (hang, plank, pull-ups, push-ups), then lift records.
struct RecordsView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var logging: Exercise?
    @State private var showingQuickLog = false

    static let benchmarkIDs = ["Dead_Hang", "Plank", "Pullups", "Pushups"]

    private var benchmarks: [Exercise] { Self.benchmarkIDs.compactMap(store.library.exercise) }

    /// Lifts you've actually done, best est. 1RM first.
    private var liftRecords: [(exercise: Exercise, best: Records.Best, trend: [(date: Date, value: Double)])] {
        store.bests.compactMap { ref, best in
            guard let exercise = store.library.exercise(ref), exercise.metric == .weightReps, best.oneRepMax > 0 else { return nil }
            return (exercise, best, store.trend(for: ref, metric: .weightReps))
        }
        .sorted { $0.best.oneRepMax > $1.best.oneRepMax }
    }

    /// Other holds and bodyweight moves you've logged beyond the four benchmarks.
    private var otherBodyweight: [(exercise: Exercise, best: Records.Best)] {
        store.bests.compactMap { ref, best in
            guard !Self.benchmarkIDs.contains(ref), let exercise = store.library.exercise(ref),
                  exercise.metric != .weightReps else { return nil }
            return (exercise, best)
        }
        .sorted { $0.exercise.name < $1.exercise.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Benchmarks").labelStyle()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(benchmarks) { exercise in
                            BenchmarkCard(exercise: exercise, trend: store.trend(for: exercise.id, metric: exercise.metric)) {
                                logging = exercise
                            }
                        }
                    }

                    if !otherBodyweight.isEmpty {
                        Text("Holds & bodyweight").labelStyle().padding(.top, 8)
                        VStack(spacing: 0) {
                            ForEach(otherBodyweight, id: \.exercise.id) { item in
                                recordRow(item.exercise.name, value: value(for: item.exercise.metric, best: item.best))
                            }
                        }
                        .padding(.horizontal, 16)
                        .card()
                    }

                    Text("Lifts").labelStyle().padding(.top, 8)
                    if liftRecords.isEmpty {
                        Text("Finish a session and your lift records show up here.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.slateText)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(liftRecords, id: \.exercise.id) { item in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.exercise.name).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
                                        Text("Heaviest \(item.best.heaviest.kg) kg").labelStyle()
                                    }
                                    Spacer()
                                    Sparkline(points: item.trend.map(\.value)).frame(width: 60, height: 24)
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("\(Int(item.best.oneRepMax.rounded()))").font(.cast(.title3)).foregroundStyle(Palette.ink)
                                        Text("est. 1RM").labelStyle()
                                    }
                                }
                                .padding(.vertical, 12)
                                Divider().overlay(Palette.rule)
                            }
                        }
                        .padding(.horizontal, 16)
                        .card()
                    }
                }
                .padding(20)
            }
            .background(Palette.bone)
            .navigationTitle("Records")
            .toolbar {
                Button {
                    showingQuickLog = true
                } label: {
                    Label("Quick log", systemImage: "plus")
                }
            }
            .sheet(item: $logging) { QuickLogView(exercise: $0) }
            .sheet(isPresented: $showingQuickLog) { QuickLogView() }
            .refreshable { await store.refresh() }
        }
    }

    private func value(for metric: ExerciseMetric, best: Records.Best) -> String {
        switch metric {
        case .duration: SetFormat.clock(best.longestHold)
        case .bodyweightReps: "\(best.mostReps) reps"
        case .weightReps: "\(best.heaviest.kg) kg"
        }
    }

    private func recordRow(_ title: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(Palette.ink)
                Spacer()
                Text(value).font(.cast(.headline)).foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 12)
            Divider().overlay(Palette.rule)
        }
    }
}

/// One benchmark: best ever, latest, trend, and a Log button.
struct BenchmarkCard: View {
    let exercise: Exercise
    let trend: [(date: Date, value: Double)]
    let onLog: () -> Void

    private func format(_ value: Double) -> String {
        exercise.metric == .duration ? SetFormat.clock(Int(value)) : "\(Int(value))"
    }

    var body: some View {
        let points = trend
        let best = points.map(\.value).max()
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name).labelStyle(Palette.ink)
            if let best {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(format(best)).font(.cast(34)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
                    Text(exercise.metric == .duration ? "" : "reps").labelStyle()
                }
                Sparkline(points: points.map(\.value)).frame(height: 28)
                if let last = points.last {
                    Text("Last \(format(last.value)) · \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .labelStyle()
                }
            } else {
                Text("–").font(.cast(34)).foregroundStyle(Palette.rule)
                Text("No result yet").labelStyle()
            }
            Button("Log", systemImage: "plus", action: onLog)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Palette.denim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }
}

/// Tiny trend line; the latest point is the orange dot.
struct Sparkline: View {
    let points: [Double]

    var body: some View {
        if points.count < 2 {
            Rectangle().fill(Palette.rule).frame(height: 1)
        } else {
            Chart(Array(points.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("i", index), y: .value("v", value))
                    .foregroundStyle(Palette.denim)
                    .interpolationMethod(.monotone)
                if index == points.count - 1 {
                    PointMark(x: .value("i", index), y: .value("v", value))
                        .foregroundStyle(Palette.orange)
                        .symbolSize(24)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (points.min() ?? 0)...(max((points.max() ?? 1), (points.min() ?? 0) + 1)))
            .accessibilityHidden(true)
        }
    }
}
