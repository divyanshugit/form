import SwiftUI

/// The Body tab: a front/back muscle map tinted by recency, with the six body parts listed below.
/// Tap a muscle or a row to open that body part's hub.
struct BodyView: View {
    @Environment(WorkoutStore.self) private var store
    @Binding var showingWorkout: Bool

    @State private var path: [BodyRoute] = []
    @State private var searching = false
    #if DEBUG
    @State private var demoExercise: Exercise?
    #endif

    enum BodyRoute: Hashable {
        case part(BodyPart)
        case records
    }

    var body: some View {
        let stats = BodyStats.compute(history: store.history, library: store.library)
        let freshness = stats.mapValues(\.freshness)
        let summary = BodyStats.summary(history: store.history)

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(summary)

                    VStack(spacing: 12) {
                        HStack(spacing: 28) {
                            figure(.front, freshness: freshness, label: "Front")
                            figure(.back, freshness: freshness, label: "Back")
                        }
                        .frame(maxWidth: .infinity)
                        FreshnessLegend()
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .card()

                    VStack(spacing: 0) {
                        ForEach(BodyPart.allCases) { part in
                            NavigationLink(value: BodyRoute.part(part)) {
                                row(part, stats: stats[part] ?? BodyPartStats())
                            }
                            .buttonStyle(.plain)
                            if part != BodyPart.allCases.last {
                                Divider().overlay(Palette.rule)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .card()
                }
                .padding(20)
            }
            .background(Palette.bone)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .navigationDestination(for: BodyRoute.self) { route in
                switch route {
                case .part(let part): BodyPartHubView(part: part, showingWorkout: $showingWorkout)
                case .records: RecordsView(embedded: true)
                }
            }
            .sheet(isPresented: $searching) { ExerciseSearchView(showingWorkout: $showingWorkout) }
            #if DEBUG
            .sheet(item: $demoExercise) { ExerciseInfoView(exercise: $0) }
            .task { demoExercise = DemoMode.exerciseID.flatMap(store.library.exercise) }
            #endif
        }
    }

    private func header(_ summary: (sessions: Int, sets: Int)) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BODY").font(.cast(32)).foregroundStyle(Palette.ink)
                Text("7 days · \(summary.sessions) sessions · \(summary.sets) sets")
                    .labelStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            HStack(spacing: 10) {
                circleButton("trophy", label: "Records") { path.append(.records) }
                circleButton("magnifyingglass", label: "Search exercises") { searching = true }
            }
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.card, in: Circle())
                .overlay(Circle().strokeBorder(Palette.rule, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    private func figure(_ side: BodyMapArtwork.Side, freshness: [BodyPart: Freshness], label: String) -> some View {
        VStack(spacing: 6) {
            MuscleMapView(side: side, freshness: freshness) { path.append(.part($0)) }
                .frame(height: 250)
            Text(label).labelStyle()
        }
    }

    private func row(_ part: BodyPart, stats: BodyPartStats) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(dotFill(stats.freshness))
                .overlay(Circle().strokeBorder(Palette.rule, lineWidth: stats.freshness == .stale ? 1.5 : 0))
                .frame(width: 10, height: 10)
            Text(part.title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Spacer()
            if stats.freshness == .stale {
                Text("DUE")
                    .font(.label)
                    .foregroundStyle(Palette.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.orange, lineWidth: 1))
            }
            Text(BodyStats.ago(stats.daysSince))
                .font(.subheadline.monospaced())
                .foregroundStyle(Palette.slateText)
            Text(stats.recentSets == 1 ? "1 set" : "\(stats.recentSets) sets")
                .font(.subheadline.monospaced())
                .foregroundStyle(Palette.slateText)
                .frame(minWidth: 58, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.slateText)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(part.title), trained \(BodyStats.ago(stats.daysSince)), \(stats.recentSets) sets in the last 7 days")
    }

    private func dotFill(_ freshness: Freshness) -> Color {
        switch freshness {
        case .fresh: Palette.orange
        case .recent: Palette.orange.opacity(0.45)
        case .stale: .clear
        }
    }
}
