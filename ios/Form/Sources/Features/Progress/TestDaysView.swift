import SwiftUI

/// The baseline test days (Nov 27–30): every test with its baseline, latest and change.
struct TestDaysView: View {
    @Environment(MetricsStore.self) private var metrics
    @Environment(WorkoutStore.self) private var store
    @State private var editing: TestKind?
    @State private var measuring: MeasureSheet.Kind?
    @State private var splitsFor: WorkoutRow?

    var body: some View {
        List {
            Section {
                Text("These become the Phase 1 starting numbers. Repeat any test later and the change shows against the baseline.")
                    .font(.subheadline).foregroundStyle(Palette.slateText)
                    .listRowBackground(Color.clear)
            }
            ForEach(Goals.testDays) { day in
                Section {
                    ForEach(day.tests) { test in
                        Button { editing = test } label: { row(test) }
                    }
                    if day.includesSplits {
                        Button { splitsFor = hyroxSession(near: day.date) } label: {
                            HStack {
                                Text("Station splits").foregroundStyle(Palette.ink)
                                Spacer()
                                Text(hyroxSession(near: day.date) == nil ? "Log the sim first" : "Enter")
                                    .foregroundStyle(Palette.slateText)
                            }
                        }
                        .disabled(hyroxSession(near: day.date) == nil)
                    }
                    if day.includesBody {
                        Button { measuring = .weight } label: { bodyRow("Weight", MetricKind.weight, unit: "kg") }
                        Button { measuring = .waist } label: { bodyRow("Waist at navel", MetricKind.waist, unit: "cm") }
                        NavigationLink("Photos: front, side, back") { PhotosView() }
                    }
                } header: {
                    Text("\(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(day.title)").labelStyle()
                }
                .listRowBackground(Palette.card)
            }
            Section {
                Button { editing = .lsitHold } label: { row(.lsitHold) }
            } header: {
                Text("Weekly skill test").labelStyle()
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bone)
        .navigationTitle("Baseline tests")
        .sheet(item: $editing) { test in TestEntrySheet(test: test) }
        .sheet(item: $measuring) { kind in MeasureSheet(kind: kind) }
        .sheet(item: $splitsFor) { session in HyroxSplitsView(session: session) }
    }

    private func hyroxSession(near date: Date) -> WorkoutRow? {
        store.history
            .filter { $0.name.localizedCaseInsensitiveContains("hyrox") }
            .min { abs($0.startedAt.timeIntervalSince(date)) < abs($1.startedAt.timeIntervalSince(date)) }
            .flatMap { abs($0.startedAt.timeIntervalSince(date)) < 4 * 86_400 ? $0 : nil }
    }

    private func row(_ test: TestKind) -> some View {
        let series = metrics.series(test.metric)
        let baseline = PhaseProgress.baseline(test, metrics: metrics.rows)
        let latest = series.last
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.title).foregroundStyle(Palette.ink)
                if let baseline {
                    Text("Baseline \(test.format(baseline.value)) · \(baseline.recordedAt.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption).foregroundStyle(Palette.slateText)
                }
            }
            Spacer()
            if let latest, let baseline, latest.id != baseline.id {
                let delta = latest.value - baseline.value
                let better = test.lowerIsBetter ? delta < 0 : delta > 0
                VStack(alignment: .trailing, spacing: 2) {
                    Text(test.format(latest.value)).font(.headline.monospacedDigit()).foregroundStyle(Palette.ink)
                    Text((delta > 0 ? "+" : "−") + test.format(abs(delta)))
                        .font(.caption.weight(.bold)).foregroundStyle(better ? Palette.orange : Palette.slateText)
                }
            } else if let latest {
                Text(test.format(latest.value)).font(.headline.monospacedDigit()).foregroundStyle(Palette.ink)
            } else {
                Text("Log").foregroundStyle(Palette.denim)
            }
        }
    }

    private func bodyRow(_ title: String, _ kind: String, unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer()
            if let latest = metrics.latest(kind) {
                Text(String(format: "%.1f %@", latest.value, unit)).foregroundStyle(Palette.ink)
            } else {
                Text("Log").foregroundStyle(Palette.denim)
            }
        }
    }
}

/// Enter one test result: minutes/seconds, metres, reps or kg.
struct TestEntrySheet: View {
    @Environment(MetricsStore.self) private var metrics
    @Environment(\.dismiss) private var dismiss
    let test: TestKind
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var number: Double = 0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch test.unit {
                    case .seconds:
                        HStack {
                            if test == .hyroxTotal { Picker("h", selection: $hours) { ForEach(0..<4) { Text("\($0) h").tag($0) } } }
                            Picker("min", selection: $minutes) { ForEach(0..<60) { Text("\($0) min").tag($0) } }
                            Picker("s", selection: $seconds) { ForEach(0..<60) { Text("\($0) s").tag($0) } }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    case .meters:
                        Stepper(String(format: "%.2f km", number / 1000), value: $number, in: 0...50_000, step: 50)
                    case .reps:
                        Stepper("\(Int(number)) reps", value: $number, in: 0...200, step: 1)
                    case .kg:
                        Stepper("\(number.kg) kg", value: $number, in: 0...400, step: 2.5)
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
            }
            .navigationTitle(test.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let value = test.unit == .seconds ? Double(hours * 3600 + minutes * 60 + seconds) : number
                        Task {
                            await metrics.record(test.metric, value, at: date)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard let latest = metrics.latest(test.metric) else {
                    number = test == .runMeters ? 6000 : 0
                    return
                }
                number = latest.value
                let total = Int(latest.value)
                hours = total / 3600; minutes = total % 3600 / 60; seconds = total % 60
            }
        }
        .presentationDetents([.medium])
    }
}

/// HYROX station splits for a sim, saved against the session.
struct HyroxSplitsView: View {
    @Environment(MetricsStore.self) private var metrics
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutRow
    @State private var splits: [HyroxStation: (min: Int, sec: Int)] = [:]
    @State private var total: (h: Int, min: Int, sec: Int) = (0, 0, 0)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(HyroxStation.allCases) { station in
                        HStack {
                            Text(station.title)
                            Spacer()
                            Picker("min", selection: binding(station, \.min)) { ForEach(0..<30) { Text("\($0)′").tag($0) } }
                                .labelsHidden()
                            Picker("s", selection: binding(station, \.sec)) { ForEach(0..<60) { Text(String(format: "%02d″", $0)).tag($0) } }
                                .labelsHidden()
                        }
                    }
                } footer: {
                    Text("Leave a station at 0:00 if you didn't do it. Splits save against this session and show up week over week.")
                }
                Section("Total") {
                    HStack {
                        Picker("h", selection: $total.h) { ForEach(0..<3) { Text("\($0) h").tag($0) } }.labelsHidden()
                        Picker("min", selection: $total.min) { ForEach(0..<60) { Text("\($0)′").tag($0) } }.labelsHidden()
                        Picker("s", selection: $total.sec) { ForEach(0..<60) { Text(String(format: "%02d″", $0)).tag($0) } }.labelsHidden()
                    }
                }
            }
            .navigationTitle("HYROX splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
            }
            .onAppear(perform: load)
        }
    }

    private func binding(_ station: HyroxStation, _ path: WritableKeyPath<(min: Int, sec: Int), Int>) -> Binding<Int> {
        Binding(get: { splits[station, default: (0, 0)][keyPath: path] },
                set: { var value = splits[station, default: (0, 0)]; value[keyPath: path] = $0; splits[station] = value })
    }

    private func load() {
        for row in metrics.metrics(for: session.id) {
            if let station = HyroxStation.allCases.first(where: { $0.metric == row.kind }) {
                splits[station] = (Int(row.value) / 60, Int(row.value) % 60)
            } else if row.kind == TestKind.hyroxTotal.metric {
                let t = Int(row.value)
                total = (t / 3600, t % 3600 / 60, t % 60)
            }
        }
        if total == (0, 0, 0), let duration = session.duration {
            let t = Int(duration)
            total = (t / 3600, t % 3600 / 60, t % 60)
        }
    }

    private func save() async {
        for station in HyroxStation.allCases {
            let value = splits[station].map { $0.min * 60 + $0.sec } ?? 0
            await metrics.setForWorkout(station.metric, value > 0 ? Double(value) : nil, workoutID: session.id, at: session.startedAt)
        }
        let t = total.h * 3600 + total.min * 60 + total.sec
        await metrics.setForWorkout(TestKind.hyroxTotal.metric, t > 0 ? Double(t) : nil, workoutID: session.id, at: session.startedAt)
        dismiss()
    }
}
