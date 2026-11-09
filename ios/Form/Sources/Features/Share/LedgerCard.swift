import SwiftUI

/// A results sheet: a highlight line, the time, three numbers, the heart-rate graph with stations marked,
/// then each HYROX station with the run before it as bars (or the lifts, when there are no splits).
struct LedgerCard: View {
    @Environment(\.cardTheme) private var composition
    let model: ShareCardModel
    var background: UIImage?
    var font: CardFont
    /// One line the data earned, e.g. "Fastest SkiErg yet · 4:30, 12 s quicker".
    var highlight: String?

    private var section: ShareCardModel.Section { model.sections[0] }
    private var theme: CardTheme { composition.over(background) }
    private var onPhoto: Bool { background != nil }

    private struct Split { let station: String; let run: Double?; let seconds: Double; let bpm: Double? }

    /// Mean heart rate between two points of the session (0–1).
    private func meanBpm(from start: Double, to end: Double) -> Double? {
        guard let curve = section.curve, curve.count > 1 else { return nil }
        let first = max(0, Int(start * Double(curve.count)))
        let last = min(curve.count, max(first + 1, Int(end * Double(curve.count))))
        return curve[first..<last].reduce(0, +) / Double(last - first)
    }

    private var splits: [Split] {
        guard let minutes = ShareCardView.minutes(section) else { return [] }
        let total = minutes * 60
        var pendingRun: Double?
        var out: [Split] = []
        for segment in section.segments {
            let seconds = (segment.end - segment.start) * total
            if segment.isStation {
                out.append(Split(station: HyroxStation.cardName(segment.label), run: pendingRun, seconds: seconds,
                                 bpm: meanBpm(from: segment.start, to: segment.end)))
                pendingRun = nil
            } else {
                pendingRun = seconds
            }
        }
        return out
    }

    var body: some View {
        let splits = splits
        ZStack(alignment: .topLeading) {
            StoryBackground(image: background)
            VStack(alignment: .leading, spacing: 0) {
                CardEyebrow(section: section, font: font)
                Spacer(minLength: 0)
                if let highlight {
                    HStack(spacing: 12) {
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                        Text(highlight).font(font.body(28)).foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.7), lineWidth: 1.5))
                    .padding(.bottom, 20)
                }
                Text(model.title).font(font.title(96)).foregroundStyle(theme.text).lineLimit(2).minimumScaleFactor(0.6)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle).font(font.subtitle(30)).foregroundStyle(theme.secondary).padding(.top, 4)
                }
                Rectangle().fill(theme.secondary).frame(height: 2.5).padding(.top, 28)

                // The time, then three numbers on one line.
                HStack(alignment: .lastTextBaseline) {
                    Text((section.heroCaption ?? "time").capitalized).font(font.body(30)).foregroundStyle(theme.secondary)
                    Spacer()
                    Text(section.hero + (section.heroUnit.map { " \($0)" } ?? "")).font(font.number(110)).foregroundStyle(theme.text)
                }
                .padding(.top, 8)
                HStack(spacing: 0) {
                    ForEach(Array(section.cardStats.prefix(3).enumerated()), id: \.offset) { index, stat in
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(stat.value).font(font.number(46)).foregroundStyle(theme.text)
                            Text(stat.label).font(font.caps(18)).tracking(1.5).textCase(.uppercase).foregroundStyle(theme.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == 2 ? .trailing : .center)
                    }
                }
                .padding(.top, 6)

                if let curve = section.curve {
                    HeartRateCurveView(curve: curve, maxHR: model.maxHR, peakBpm: section.peakBpm, peakAt: section.peakAt,
                                       avgBpm: section.avgBpm, segments: section.segments, font: font)
                        .frame(height: splits.isEmpty ? 330 : 250).padding(.top, 30)
                }

                if !splits.isEmpty {
                    splitsTable(splits).padding(.top, 26)
                } else if !section.lines.isEmpty {
                    lifts.padding(.top, 26)
                }
                CardFooter(text: model.footer, font: font).padding(.top, 26)
            }
            .padding(CardMetrics.insets)
            .legible(onPhoto: onPhoto)
        }
        .storyFrame()
        .environment(\.cardTheme, theme)
    }

    /// Station rows: the run before it (muted) and the station (zone colour) as bars on one scale.
    private func splitsTable(_ splits: [Split]) -> some View {
        let longest = splits.map { ($0.run ?? 0) + $0.seconds }.max() ?? 1
        return VStack(spacing: 10) {
            HStack {
                Text("STATION").frame(width: 200, alignment: .leading)
                Text("RUN  +  STATION")
                Spacer()
                Text("TIME").frame(width: 92, alignment: .trailing)
                Text("BPM").frame(width: 58, alignment: .trailing)
            }
            .font(font.caps(17)).tracking(2).foregroundStyle(theme.tertiary)
            ForEach(Array(splits.enumerated()), id: \.offset) { _, split in
                let zone = split.bpm.map { HeartRateCurve.zone($0, maxHR: model.maxHR) } ?? 0
                HStack(spacing: 0) {
                    Text(split.station).font(font.body(26)).foregroundStyle(theme.text).lineLimit(1)
                        .frame(width: 200, alignment: .leading)
                    GeometryReader { geo in
                        HStack(spacing: 4) {
                            if let run = split.run {
                                Capsule().fill(theme.hairline).frame(width: geo.size.width * CGFloat(run / longest))
                            }
                            Capsule().fill(theme.zones[zone]).frame(width: geo.size.width * CGFloat(split.seconds / longest))
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 18)
                    Text(ShareCards.duration(split.seconds))
                        .font(font.number(32)).foregroundStyle(theme.text).frame(width: 92, alignment: .trailing)
                    Text(split.bpm.map { "\(Int($0.rounded()))" } ?? "–").font(font.caps(19))
                        .foregroundStyle(theme.zones[zone]).frame(width: 58, alignment: .trailing)
                }
                .frame(height: 42)
            }
        }
    }

    /// Lifts as a list with dotted leaders to the sets.
    private var lifts: some View {
        VStack(spacing: 0) {
            ForEach(section.lines, id: \.self) { line in
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    Text(line.name).font(font.body(28)).foregroundStyle(theme.secondary)
                    if line.isPR { PRBadge(font: font, size: 18) }
                    DotLeader()
                    Text(line.detail).font(font.number(36)).foregroundStyle(theme.text)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private struct DotLeader: View {
        @Environment(\.cardTheme) private var theme
        var body: some View {
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height - 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 2))
                }
                .stroke(theme.hairline, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 10]))
            }
            .frame(height: 6)
        }
    }
}

/// "PR" in the accent, next to a lift.
struct PRBadge: View {
    @Environment(\.cardTheme) private var theme
    var font: CardFont
    var size: CGFloat = 20

    var body: some View {
        Text("PR").font(font.caps(size)).foregroundStyle(theme.bg)
            .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.2)
            .background(theme.accent, in: Capsule())
    }
}
