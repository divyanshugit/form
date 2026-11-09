import SwiftUI

/// The motivation screen: everything done since Day 1, then vs now, and the PRs and milestones gained.
struct SinceDayOneView: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(MetricsStore.self) private var metrics
    @Environment(PhotoStore.self) private var photos
    @State private var firstImage: UIImage?
    @State private var latestImage: UIImage?
    @State private var comparing = false
    @State private var sharing = false

    var body: some View {
        let snapshot = ProgressSnapshot(store: store, metrics: metrics, photos: photos)
        let since = snapshot.since
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day \(snapshot.dayNumber)").font(.system(size: 54, weight: .regular, design: .serif)).foregroundStyle(Palette.ink)
                    Text("\(since.weeks) weeks since \(Goals.dayZero.formatted(.dateTime.day().month(.wide))). Look how far that is.")
                        .font(.subheadline).foregroundStyle(Palette.slateText)
                }
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("\(since.daysTrained)", "days trained")
                    tile("\(since.sessions)", "sessions")
                    tile(String(format: "%.0f", since.hours), "hours")
                    tile("\(since.prs)", "PRs")
                    tile("\(snapshot.achievedCount)", "milestones")
                    tile("\(since.hyroxSims)", "HYROX sims")
                    if since.kilometres > 0 { tile(String(format: "%.0f", since.kilometres), "km run") }
                    if let change = snapshot.weightChange { tile(String(format: "%+.1f", change), "kg") }
                }

                thenVsNow

                let done = snapshot.milestones.filter(\.isDone).sorted { ($0.achievedOn ?? .distantPast) > ($1.achievedOn ?? .distantPast) }
                if !done.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Unlocked").labelStyle()
                        ForEach(done) { status in
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.orange)
                                Text(status.milestone.title).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(status.achievedOn!.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(Palette.slateText)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                hyroxTrend

                Button { sharing = true } label: { Label("Share progress card", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.bone)
        .navigationTitle("Since Day 1")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhotos() }
        .sheet(isPresented: $comparing) {
            if let first = sortedPhotos.first, let last = sortedPhotos.last { CompareView(older: first, newer: last) }
        }
        .sheet(isPresented: $sharing) {
            ShareCardSheet(model: ShareCards.progress(since, weightChange: snapshot.weightChange,
                                                      milestones: snapshot.achievedCount, dayNumber: snapshot.dayNumber))
        }
    }

    private var sortedPhotos: [ProgressPhoto] { photos.photos.sorted { $0.takenAt < $1.takenAt } }

    private func loadPhotos() async {
        guard let first = sortedPhotos.first, let last = sortedPhotos.last, first.id != last.id else { return }
        async let a = photos.thumbnail(for: first)
        async let b = photos.thumbnail(for: last)
        (firstImage, latestImage) = await (a, b)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.cast(32)).foregroundStyle(Palette.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(Palette.slateText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var thenVsNow: some View {
        if let firstImage, let latestImage, let first = sortedPhotos.first, let last = sortedPhotos.last {
            Button { comparing = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Then vs now").labelStyle()
                    HStack(spacing: 4) {
                        photo(firstImage, "Day \(photos.dayNumber(first))")
                        photo(latestImage, "Day \(photos.dayNumber(last))")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(PhotoTimeline.change(from: first, to: last)).font(.headline).foregroundStyle(Palette.ink)
                }
                .padding(18)
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private func photo(_ image: UIImage, _ label: String) -> some View {
        Image(uiImage: image).resizable().scaledToFill()
            .frame(maxWidth: .infinity).frame(height: 230).clipped()
            .overlay(alignment: .bottomLeading) {
                Text(label).labelStyle(.white).padding(8)
            }
    }

    /// Saturday sims week over week: strain and heart rate, the first proof fitness is rising.
    @ViewBuilder
    private var hyroxTrend: some View {
        let sims = store.history.filter { $0.name.localizedCaseInsensitiveContains("hyrox") }.sorted { $0.startedAt < $1.startedAt }
        if sims.count >= 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("HYROX sims").labelStyle()
                ForEach(sims.suffix(8)) { sim in
                    let total = metrics.metrics(for: sim.id).first { $0.kind == TestKind.hyroxTotal.metric }
                    HStack {
                        Text(sim.startedAt.formatted(.dateTime.day().month(.abbreviated))).frame(width: 64, alignment: .leading)
                        Text(total.map { TestKind.hyroxTotal.format($0.value) } ?? sim.duration.map(ShareCards.duration) ?? "—")
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        if let strain = sim.strain { Text(String(format: "%.1f strain", strain)) }
                        if let avg = sim.avgHr { Text("\(avg) bpm").foregroundStyle(Palette.slateText) }
                    }
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
