import PhotosUI
import SwiftUI

// MARK: - Rendering and sharing

enum ShareCardRenderer {
    @MainActor
    static func render(_ card: ShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(CardMetrics.size)
        return renderer.uiImage
    }
}

/// Preview, edit the headline, pick a background photo, share.
struct ShareCardSheet: View {
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @State var model: ShareCardModel
    var allowsTitleEdit = true

    @State private var background: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var rendered: UIImage?
    @State private var useLatestPhoto = false
    @State private var curveStatus: String?
    /// Last time's curve, loaded once; shown only when the switch is on.
    @State private var lastTime: (curve: [Double], minutes: Double, label: String)?
    @State private var compare = false
    @AppStorage("share.font") private var font: CardFont = .editorial
    @AppStorage("share.layout") private var layout: CardLayout = .current
    @AppStorage("share.palette") private var palette: CardPalette = .graphite
    @AppStorage("share.background") private var plain: PlainBackground = .washGrid
    /// The Ledger's highlight line: filled in from the data, editable, and can be switched off.
    @State private var highlight = ""
    @State private var showHighlight = true
    @Environment(WorkoutStore.self) private var store
    @Environment(MetricsStore.self) private var metrics

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    if allowsTitleEdit {
                        TextField("Headline", text: $model.title)
                            .font(.title3.weight(.semibold))
                            .padding(14)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    let layouts = CardLayout.allCases.filter { $0.available(for: model) }
                    if layouts.count > 1 {
                        Picker("Layout", selection: $layout) {
                            ForEach(layouts) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Colours", selection: $palette) {
                        ForEach(CardPalette.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if background == nil {
                        Picker("Background", selection: $plain) {
                            ForEach(PlainBackground.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Font", selection: $font) {
                        ForEach(CardFont.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if layout.resolved(for: model) == .ledger {
                        HStack(spacing: 10) {
                            TextField("Highlight, e.g. Fastest SkiErg yet", text: $highlight)
                                .padding(14)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                                .opacity(showHighlight ? 1 : 0.4)
                                .disabled(!showHighlight)
                            Toggle("Show highlight", isOn: $showHighlight).labelsHidden().tint(Palette.orange)
                        }
                    }
                    if let lastTime {
                        Toggle(isOn: $compare) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Compare with last time")
                                Text(lastTime.label).font(.footnote).foregroundStyle(Palette.slateText)
                            }
                        }
                        .tint(Palette.orange)
                    }
                    if let curveStatus {
                        Text(curveStatus).font(.footnote).foregroundStyle(Palette.slateText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $picked, matching: .images) {
                            Label("Photo", systemImage: "photo")
                        }
                        .buttonStyle(InkPillStyle())
                        if !photos.photos.isEmpty {
                            Button("Latest progress") { Task { await loadLatest() } }
                                .buttonStyle(InkPillStyle())
                        }
                        if background != nil {
                            Button("Plain") { background = nil; rerender() }
                                .buttonStyle(InkPillStyle())
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.bone)
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let rendered {
                        ShareLink(item: Image(uiImage: rendered), preview: SharePreview(model.title, image: Image(uiImage: rendered))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear(perform: rerender)
            .task { await loadCurves() }
            .onChange(of: model.title) { _, _ in rerender() }
            .onChange(of: font) { _, _ in rerender() }
            .onChange(of: layout) { _, _ in rerender() }
            .onChange(of: palette) { _, _ in rerender() }
            .onChange(of: plain) { _, _ in rerender() }
            .onChange(of: highlight) { _, _ in rerender() }
            .onChange(of: showHighlight) { _, _ in rerender() }
            .onChange(of: compare) { _, _ in applyComparison() }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        background = BoardImport.image(data, maxPixel: 2200)
                        rerender()
                    }
                }
            }
        }
    }

    private var preview: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered).resizable().scaledToFit()
            } else {
                Rectangle().fill(Palette.navy).aspectRatio(9 / 16, contentMode: .fit).overlay(ProgressView())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: 520)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    /// Heart-rate curves from Apple Health (WHOOP writes them there when its Health integration is on).
    private func loadCurves() async {
        addSegments()
        suggestHighlight()
        let timed = model.sections.filter { $0.start != nil && $0.end != nil }
        guard !timed.isEmpty, HealthHeartRate.isAvailable else { return }
        model.maxHR = HeartRateCurve.maxHR(history: store.history)
        let curves = await HealthHeartRate.curves(for: model.sections)
        for (index, curve) in curves {
            model.sections[index].curve = curve.points
            model.sections[index].peakAt = curve.peak?.at
            // WHOOP's max is what the card's "max bpm" says; fall back to the highest Health sample.
            if model.sections[index].peakBpm == nil { model.sections[index].peakBpm = curve.peak?.bpm }
        }
        if model.sections.count == 1, model.sections[0].curve != nil { await addGhost() }
        if curves.count < timed.count {
            curveStatus = curves.isEmpty
                ? "No heart-rate samples in Apple Health for this time. In the WHOOP app, turn on the Apple Health integration with heart rate, then let it sync."
                : "Some sessions have no heart-rate samples in Apple Health, so they show zone bars only."
        } else {
            curveStatus = nil
        }
        rerender()
    }

    /// HYROX station splits logged for a session, laid on its timeline.
    private func addSegments() {
        for index in model.sections.indices {
            guard let id = model.sections[index].workoutID,
                  let workout = store.history.first(where: { $0.id == id }),
                  let seconds = workout.duration else { continue }
            let race = ShareCards.hyroxSplits(metrics.metrics(for: id))
            model.sections[index].segments = ShareCards.hyroxSegments(splits: race.splits, total: race.total, sessionSeconds: seconds)
        }
    }

    /// What the session earned, as the Ledger's opening line; left alone once there's text.
    private func suggestHighlight() {
        guard highlight.isEmpty, model.sections.count == 1, let id = model.sections[0].workoutID,
              let workout = store.history.first(where: { $0.id == id }) else { return }
        let splits = ShareCards.hyroxSplits(metrics.metrics(for: id)).splits
        let prs = model.sections[0].lines.filter(\.isPR).map(\.name)
        highlight = ShareCards.highlight(for: workout, prs: prs, splits: splits, metrics: metrics.rows, history: store.history) ?? ""
    }

    /// The previous session of the same name, from Apple Health, behind today's curve.
    private func addGhost() async {
        guard let id = model.sections[0].workoutID,
              let workout = store.history.first(where: { $0.id == id }),
              let previous = ShareCards.previous(of: workout, in: store.history),
              let end = previous.endedAt else { return }
        let samples = await HealthHeartRate.samples(from: previous.startedAt, to: end)
        guard let curve = HeartRateCurve.resample(samples, start: previous.startedAt, end: end) else { return }
        lastTime = (curve, end.timeIntervalSince(previous.startedAt) / 60, ShareCards.comparisonLabel(workout, previous: previous))
        applyComparison()
    }

    /// Off by default: the dotted line and its legend only go on the card when asked for.
    private func applyComparison() {
        guard model.sections.count == 1 else { return }
        let shown = compare ? lastTime : nil
        model.sections[0].ghost = shown?.curve
        model.sections[0].ghostMinutes = shown?.minutes
        model.sections[0].ghostLabel = shown?.label
        rerender()
    }

    private func loadLatest() async {
        guard let latest = photos.photos.max(by: { $0.takenAt < $1.takenAt }) else { return }
        background = await photos.image(for: latest)
        rerender()
    }

    private func rerender() {
        let line = highlight.trimmingCharacters(in: .whitespaces)
        rendered = ShareCardRenderer.render(ShareCard(model: model, background: background, font: font, layout: layout, palette: palette,
                                                      highlight: showHighlight && !line.isEmpty ? line : nil, plain: plain))
    }
}
