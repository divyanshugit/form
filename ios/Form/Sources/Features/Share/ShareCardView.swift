import SwiftUI

/// The story card, drawn at 1080 × 1920 points (rendered at scale 1 → 1080 × 1920 px).
struct ShareCardView: View {
    let model: ShareCardModel
    var background: UIImage?
    var font: CardFont = .editorial

    @Environment(\.cardTheme) private var composition
    private var theme: CardTheme { composition.over(background) }

    private var isSingle: Bool { model.banner == nil && model.sections.count == 1 }

    /// One bpm scale for every curve on the card, so the same heart rate sits at the same height everywhere.
    private var bpmRange: ClosedRange<Double> {
        HeartRateCurveView.range(for: model.sections, maxHR: model.maxHR)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            Group {
                if isSingle, let section = model.sections.first {
                    single(section)
                } else {
                    stacked
                }
            }
            .padding(.horizontal, CardMetrics.insets.leading)
            .storyFrame(alignment: .topLeading)
            .legible(onPhoto: background != nil)
        }
        .storyFrame()
        .environment(\.cardTheme, theme)
        .environment(\.colorScheme, .dark)
    }

    private var backdrop: some View {
        StoryBackground(image: background)
    }

    private var footer: some View {
        CardFooter(text: model.footer, font: font)
    }

    // MARK: Single session

    /// One session: the date and name up top, the hero number, then the curve and numbers anchored low.
    private func single(_ section: ShareCardModel.Section) -> some View {
        let stats = section.cardStats
        let hasLines = !section.lines.isEmpty
        // The chart takes the spare room (up to a cap) so the card never has a hole in the middle.
        let chartRange: ClosedRange<CGFloat> = hasLines ? 260...440 : 380...680
        return VStack(alignment: .leading, spacing: 0) {
            CardEyebrow(section: section, font: font, italic: true)
            Text(model.title)
                .font(font.title(84))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .padding(.top, 18)
            if !model.subtitle.isEmpty {
                Text(model.subtitle).font(font.subtitle(30)).foregroundStyle(theme.tertiary).padding(.top, 12)
            }

            Spacer(minLength: 60)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(section.hero)
                        .font(font.display(hasLines ? 170 : 210))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let unit = section.heroUnit {
                        Text(unit).font(font.body(56)).foregroundStyle(theme.secondary)
                    }
                }
                if let caption = section.heroCaption {
                    Text(caption).font(font.caps(22)).tracking(3).textCase(.uppercase).foregroundStyle(theme.tertiary)
                }
            }

            if let curve = section.curve {
                HeartRateCurveView(curve: curve, maxHR: model.maxHR, range: bpmRange, peakBpm: section.peakBpm, peakAt: section.peakAt,
                                   avgBpm: section.avgBpm, minutes: Self.minutes(section), showAxis: true, segments: section.segments,
                                   ghost: section.ghost, ghostMinutes: section.ghostMinutes, font: font)
                    .frame(minHeight: chartRange.lowerBound, maxHeight: chartRange.upperBound)
                    .layoutPriority(1)
                    .padding(.top, 44)
                if let ghostLabel = section.ghostLabel {
                    ghostLegend(ghostLabel).padding(.top, 18)
                }
            } else if let zones = section.zones, zones.reduce(0, +) > 0 {
                ZoneColumns(zones: zones, font: font)
                    .frame(minHeight: chartRange.lowerBound - 40, maxHeight: chartRange.upperBound - 40)
                    .layoutPriority(1)
                    .padding(.top, 44)
            }

            if !stats.isEmpty {
                CardStatRow(stats: stats, font: font).padding(.top, 44)
            }

            if let zones = section.zones, zones.reduce(0, +) > 0, section.curve != nil {
                ZoneLegend(zones: zones, font: font).padding(.top, 40)
            }

            if hasLines {
                VStack(spacing: 0) {
                    ForEach(section.lines, id: \.self) { line in
                        exerciseRow(line)
                    }
                }
                .padding(.top, 36)
            }

            footer.padding(.top, 44)
        }
        .padding(.top, CardMetrics.insets.top)
        .padding(.bottom, CardMetrics.insets.bottom)
    }

    private func ghostLegend(_ label: String) -> some View {
        HStack(spacing: 28) {
            HStack(spacing: 10) {
                Capsule().fill(LinearGradient(colors: [theme.zones[3], theme.zones[5]], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 34, height: 5)
                Text("today").font(font.caps(20)).tracking(2).textCase(.uppercase)
            }
            HStack(spacing: 10) {
                HStack(spacing: 5) { ForEach(0..<4) { _ in Circle().frame(width: 5, height: 5) } }
                Text(label).font(font.caps(20)).tracking(2).textCase(.uppercase)
            }
            Spacer()
        }
        .foregroundStyle(theme.tertiary)
    }

    private func exerciseRow(_ line: ShareCardModel.Line) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack {
                Text(line.name).font(font.body(32)).foregroundStyle(theme.text).lineLimit(1)
                if line.isPR { PRBadge(font: font) }
                Spacer()
                Text(line.detail).font(font.number(30)).foregroundStyle(theme.secondary)
            }
            .padding(.vertical, 16)
        }
    }

    static func eyebrow(_ start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM · H:mm"
        return formatter.string(from: start).uppercased()
    }

    static func minutes(_ section: ShareCardModel.Section) -> Double? {
        guard let start = section.start, let end = section.end else { return nil }
        return end.timeIntervalSince(start) / 60
    }

    // MARK: Several sessions, week, milestone, progress

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .font(font.title(76))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(model.subtitle)
                .font(font.subtitle(30))
                .foregroundStyle(theme.secondary)
                .padding(.top, 14)

            if let banner = model.banner {
                bannerBlock(banner)
            }
            ForEach(Array(sectionsToShow.enumerated()), id: \.offset) { index, section in
                if index > 0 || model.banner != nil { divider }
                sectionView(section, first: index == 0)
            }
            Spacer(minLength: 0)
            if let combined = model.combinedZones, model.sections.count < 3 {
                Text("Combined").font(font.body(26)).foregroundStyle(theme.secondary).padding(.top, 24).padding(.bottom, 22)
                ZoneBar(zones: combined, height: 14, labelSize: 22, labelColor: theme.secondary, showPercent: true)
                    .padding(.bottom, 40)
            }
            footer
        }
        .padding(.top, model.sections.count >= 3 ? 120 : 150)
        .padding(.bottom, model.sections.count >= 3 ? 64 : 80)
    }

    /// Long weeks list sessions compactly; a recap draws every section in full.
    private var sectionsToShow: [ShareCardModel.Section] {
        model.banner != nil ? Array(model.sections.prefix(7)) : Array(model.sections.prefix(3))
    }

    private var curveHeight: CGFloat {
        model.sections.count == 2 ? 230 : 140
    }

    private var divider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1).padding(.vertical, model.sections.count >= 3 ? 30 : 44)
    }

    private func bannerBlock(_ banner: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(banner)
                .font(font.display(128))
                .foregroundStyle(theme.text)
                .lineLimit(3)
                .minimumScaleFactor(0.4)
            if let detail = model.bannerDetail {
                Text(detail).font(font.body(34)).foregroundStyle(theme.secondary)
            }
            if !model.stats.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(model.stats, id: \.self) { stat in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(stat.value).font(font.number(54)).foregroundStyle(theme.text)
                            Text(stat.label).font(font.body(24)).foregroundStyle(theme.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 30)
            }
        }
        .padding(.top, 110)
    }

    @ViewBuilder
    private func sectionView(_ section: ShareCardModel.Section, first: Bool) -> some View {
        if model.banner != nil {
            // Compact row (week card).
            HStack {
                Text(section.label).font(font.body(28)).foregroundStyle(theme.tertiary).frame(width: 110, alignment: .leading)
                Text(section.hero).font(font.body(34)).foregroundStyle(theme.text).lineLimit(1)
                Spacer()
                Text(section.stats.first?.value ?? "").font(font.number(30)).foregroundStyle(theme.secondary)
            }
            .padding(.top, -28)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.label).font(font.body(28)).foregroundStyle(theme.secondary)
                    .padding(.top, first ? (model.sections.count >= 3 ? 64 : 110) : 0)
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(section.hero).font(font.display(model.sections.count >= 3 ? 92 : 112)).foregroundStyle(theme.text)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if let unit = section.heroUnit {
                            Text(unit).font(font.body(40)).foregroundStyle(theme.secondary)
                        }
                    }
                    Spacer(minLength: 20)
                    HStack(alignment: .top, spacing: 44) {
                        ForEach(section.stats, id: \.self) { stat in
                            VStack(alignment: .trailing, spacing: 12) {
                                Text(stat.value).font(font.number(40)).foregroundStyle(theme.text)
                                Text(stat.label).font(font.body(24)).foregroundStyle(theme.tertiary)
                            }
                        }
                    }
                }
                .padding(.top, 20)
                if let curve = section.curve {
                    HeartRateCurveView(curve: curve, maxHR: model.maxHR, range: bpmRange, peakBpm: section.peakBpm, peakAt: section.peakAt,
                                       avgBpm: section.avgBpm, segments: section.segments, font: font)
                        .frame(height: curveHeight)
                        .padding(.top, model.sections.count >= 3 ? 24 : 40)
                }
                if !section.lines.isEmpty && section.curve == nil {
                    VStack(spacing: 18) {
                        ForEach(section.lines, id: \.self) { line in
                            HStack {
                                Text(line.name).font(font.body(32)).foregroundStyle(theme.text).lineLimit(1)
                                if line.isPR { PRBadge(font: font, size: 22) }
                                Spacer()
                                Text(line.detail).font(font.number(32)).foregroundStyle(theme.secondary)
                            }
                        }
                    }
                    .padding(.top, 44)
                }
                if section.curve == nil, let zones = section.zones, zones.reduce(0, +) > 0 {
                    ZoneBar(zones: zones, height: 14, labelSize: 22, labelColor: theme.secondary).padding(.top, model.sections.count >= 3 ? 26 : 50)
                }
            }
        }
    }
}

/// Six segments sized by time in zone, labelled Z0–Z5 (and the share of time) underneath.
struct ZoneBar: View {
    @Environment(\.cardTheme) private var theme
    let zones: [Int]
    var height: CGFloat = 8
    var labelSize: CGFloat = 11
    var labelColor: Color = .white.opacity(0.8)
    var showPercent = false

    var body: some View {
        let values = (0..<6).map { zones.count > $0 ? zones[$0] : 0 }
        let total = max(1, values.reduce(0, +))
        GeometryReader { geo in
            let gap: CGFloat = height * 0.5
            let usable = geo.size.width - gap * 5
            // Every zone keeps room for its label; the rest is shared by time in zone.
            let minimum = min(usable / 6, labelSize * (showPercent ? 2.6 : 1.6))
            let spare = usable - minimum * 6
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: height * 0.9) {
                        Capsule().fill(theme.zones[i]).frame(height: height)
                            .opacity(values[i] == 0 ? 0.25 : 1)
                        VStack(spacing: 2) {
                            Text("Z\(i)").font(.system(size: labelSize)).foregroundStyle(labelColor)
                            if showPercent {
                                Text("\(Int((Double(values[i]) / Double(total) * 100).rounded()))%")
                                    .font(.system(size: labelSize * 0.85, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(values[i] == 0 ? labelColor.opacity(0.4) : theme.zones[i])
                            }
                        }
                        .fixedSize()
                    }
                    .frame(width: minimum + spare * CGFloat(values[i]) / CGFloat(total))
                }
            }
        }
        .frame(height: height * 1.9 + labelSize * (showPercent ? 2.4 : 1.3))
    }
}

/// Share of time in each zone, as a compact row: a colour dot, the zone, the percentage.
struct ZoneLegend: View {
    @Environment(\.cardTheme) private var theme
    let zones: [Int]
    var font: CardFont = .editorial

    var body: some View {
        let values = (0..<6).map { zones.count > $0 ? zones[$0] : 0 }
        let total = max(1, values.reduce(0, +))
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let share = Int((Double(values[i]) / Double(total) * 100).rounded())
                HStack(spacing: 10) {
                    Circle().fill(theme.zones[i]).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Z\(i)").font(font.caps(18)).foregroundStyle(theme.tertiary)
                        Text("\(share)%").font(font.number(28)).foregroundStyle(share == 0 ? theme.tertiary : theme.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// When there's no heart-rate curve: minutes in each zone as columns.
struct ZoneColumns: View {
    @Environment(\.cardTheme) private var theme
    let zones: [Int]
    var font: CardFont = .editorial

    var body: some View {
        let minutes = (0..<6).map { Double(zones.count > $0 ? zones[$0] : 0) / 60_000 }
        let top = max(1, minutes.max() ?? 1)
        GeometryReader { geo in
            let labelRoom: CGFloat = 92
            let barArea = geo.size.height - labelRoom
            HStack(alignment: .bottom, spacing: 22) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(spacing: 10) {
                        Text(minutes[i] >= 1 ? "\(Int(minutes[i].rounded()))m" : "–")
                            .font(font.number(28))
                            .foregroundStyle(minutes[i] >= 1 ? theme.text : theme.tertiary)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [theme.zones[i], theme.zones[i].opacity(0.55)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(height: max(8, (barArea - 40) * CGFloat(minutes[i] / top)))
                        Text("Z\(i)").font(font.caps(22)).foregroundStyle(theme.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}

/// The heart-rate line, coloured by zone, over faint zone bands, with the peak and average marked.
struct HeartRateCurveView: View {
    @Environment(\.cardTheme) private var theme
    let curve: [Double]
    let maxHR: Double
    /// The bpm scale; shared across a card so curves compare. Defaults to this curve's own.
    var range: ClosedRange<Double>? = nil
    /// The true max and when it happened (0–1); without them the curve's own top is used.
    var peakBpm: Double? = nil
    var peakAt: Double? = nil
    /// The true average; without it, the curve's mean.
    var avgBpm: Double? = nil
    /// Session length; with `showAxis`, labels the time along the bottom.
    var minutes: Double? = nil
    var showAxis = false
    /// HYROX stations, shaded behind the line.
    var segments: [ShareCardModel.Segment] = []
    /// The previous session, dotted behind today's line, by elapsed time.
    var ghost: [Double]? = nil
    var ghostMinutes: Double? = nil
    var font: CardFont = .editorial

    /// The scale that fits every curve, ghost and true peak on a card, with the zone 1–5 floors in view.
    static func range(for sections: [ShareCardModel.Section], maxHR: Double) -> ClosedRange<Double> {
        let values = sections.flatMap { ($0.curve ?? []) + ($0.ghost ?? []) + [$0.peakBpm].compactMap { $0 } }
        let low = min(values.min() ?? maxHR * 0.5, maxHR * 0.5) - 6
        let high = max(values.max() ?? maxHR, maxHR * 0.92) + 6
        return low...high
    }

    /// How strongly the area under the line is tinted at its top.
    private static let areaOpacity = 0.14

    var body: some View {
        Canvas { context, size in
            let peak = max(peakBpm ?? 0, curve.max() ?? maxHR)
            let average = avgBpm ?? curve.reduce(0, +) / Double(max(1, curve.count))
            let scale = range ?? Self.range(for: [.init(label: "", hero: "", curve: curve, peakBpm: peak, ghost: ghost)], maxHR: maxHR)
            let low = scale.lowerBound, high = scale.upperBound
            let labelRoom: CGFloat = 40
            let stripHeight: CGFloat = showAxis ? 22 : 14
            let stripRoom: CGFloat = stripHeight + (showAxis ? 14 : 12)
            let axisRoom: CGFloat = showAxis ? 44 : 0
            let rightRoom: CGFloat = showAxis ? 52 : 0
            let plot = CGRect(x: 0, y: labelRoom, width: size.width - rightRoom,
                              height: size.height - labelRoom - stripRoom - axisRoom)
            /// Where a share of the session (0–1) sits across the plot, and where a heart rate sits up it.
            func x(_ share: Double) -> CGFloat { plot.minX + plot.width * CGFloat(share) }
            func y(_ bpm: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((bpm - low) / (high - low)) }
            func point(_ index: Int) -> CGPoint { CGPoint(x: x(Double(index) / Double(max(1, curve.count - 1))), y: y(curve[index])) }

            // HYROX stations: shaded bands with their names along the bottom of the plot.
            for segment in segments where segment.isStation {
                let startX = x(segment.start), endX = x(min(1, segment.end))
                guard endX > startX else { continue }
                for edgeX in [startX, endX] {
                    var edge = Path()
                    edge.move(to: CGPoint(x: edgeX, y: plot.minY))
                    edge.addLine(to: CGPoint(x: edgeX, y: plot.maxY))
                    context.stroke(edge, with: .color(theme.hairline), style: StrokeStyle(lineWidth: 1.5, dash: [2, 6]))
                }
                let labelSize: CGFloat = showAxis ? 17 : 14
                if endX - startX >= CGFloat(segment.label.count) * labelSize * 0.68 + 6 {
                    context.draw(Text(segment.label).font(.system(size: labelSize, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.secondary),
                                 at: CGPoint(x: (startX + endX) / 2, y: plot.maxY - labelSize))
                }
            }

            // Gridlines at zone 2–5 floors, labelled on the right.
            for (zone, floor) in HeartRateCurve.zoneFloors.enumerated().dropFirst(2) where floor * maxHR > low && floor * maxHR < high {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y(floor * maxHR)))
                line.addLine(to: CGPoint(x: plot.maxX, y: y(floor * maxHR)))
                context.stroke(line, with: .color(theme.hairline), lineWidth: 1.5)
                if showAxis {
                    context.draw(Text("Z\(zone)").font(.system(size: 20, weight: .semibold)).foregroundColor(theme.zones[zone]),
                                 at: CGPoint(x: plot.maxX + rightRoom / 2 + 6, y: y(floor * maxHR)))
                }
            }

            // One smooth line through the samples, and the same colours blended along it from zone to zone.
            let line = Path.smoothed(through: curve.indices.map(point))
            // Coloured by height: each zone keeps its colour and blends into the next as the line crosses it.
            let along = theme.zoneShading(maxHR: maxHR, range: low...high, bottom: plot.maxY, top: plot.minY)

            // Under the line: one soft tint of the type colour, fading out towards the bottom.
            var area = line
            area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [theme.text.opacity(Self.areaOpacity), .clear]),
                                                     startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))

            // Average line.
            var avgLine = Path()
            avgLine.move(to: CGPoint(x: plot.minX, y: y(average)))
            avgLine.addLine(to: CGPoint(x: plot.maxX, y: y(average)))
            context.stroke(avgLine, with: .color(theme.tertiary), style: StrokeStyle(lineWidth: 2, dash: [8, 10]))
            if showAxis {
                let pill = CGRect(x: plot.maxX - 98, y: y(average) + 4, width: 96, height: 30)
                context.fill(Path(roundedRect: pill, cornerRadius: 15), with: .color(theme.bg.opacity(0.85)))
                context.draw(Text("avg \(Int(average.rounded()))").font(.system(size: 20, weight: .semibold)).foregroundColor(theme.tertiary),
                             at: CGPoint(x: plot.maxX - 50, y: y(average) + 19))
            }

            // Last time, by elapsed minutes on today's axis (or by share of the session without times).
            if let ghost, ghost.count > 1 {
                var path = Path()
                for index in ghost.indices {
                    let share = Double(index) / Double(ghost.count - 1)
                    let position = (minutes.flatMap { today in ghostMinutes.map { share * $0 / today } }) ?? share
                    guard position <= 1 else { break }
                    let sample = CGPoint(x: x(position), y: y(ghost[index]))
                    index == 0 ? path.move(to: sample) : path.addLine(to: sample)
                }
                context.stroke(path, with: .color(theme.tertiary),
                               style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0.1, 9]))
            }

            // Glow, then the line.
            context.drawLayer { layer in
                layer.opacity = 0.25
                layer.stroke(line, with: along, style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            }
            context.stroke(line, with: along, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            // Peak: the same marker on every curve — a ring at the true max, at the moment it happened,
            // joined to the line by a hairline when smoothing has pulled the line below it.
            let peakIndex = peakAt.map { min(curve.count - 1, max(0, Int(($0 * Double(curve.count - 1)).rounded()))) }
                ?? curve.indices.max(by: { curve[$0] < curve[$1] })
            if let index = peakIndex {
                let onLine = point(index)
                let top = CGPoint(x: onLine.x, y: y(peak))
                if onLine.y - top.y > 4 {
                    var stem = Path()
                    stem.move(to: onLine)
                    stem.addLine(to: top)
                    context.stroke(stem, with: .color(theme.secondary), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                }
                let zone = HeartRateCurve.zone(peak, maxHR: maxHR)
                let radius: CGFloat = showAxis ? 11 : 9
                context.fill(Path(ellipseIn: CGRect(x: top.x - radius, y: top.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(theme.text))
                context.fill(Path(ellipseIn: CGRect(x: top.x - radius + 4, y: top.y - radius + 4, width: radius * 2 - 8, height: radius * 2 - 8)),
                             with: .color(theme.zones[zone]))
                let label = Text("MAX \(Int(peak.rounded()))")
                    .font(.system(size: showAxis ? 22 : 19, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.text)
                let resolved = context.resolve(label)
                let width = resolved.measure(in: size).width
                // Kept inside the plot so it never runs off the card or into the zone labels.
                let labelX = min(max(top.x, plot.minX + width / 2), plot.maxX - width / 2)
                context.draw(resolved, at: CGPoint(x: labelX, y: top.y - radius - 16))
            }

            // Zone strip: the session minute by minute, coloured by zone.
            let strip = CGRect(x: plot.minX, y: plot.maxY + (showAxis ? 14 : 12), width: plot.width, height: stripHeight)
            var stripContext = context
            stripContext.clip(to: Path(roundedRect: strip, cornerRadius: stripHeight / 2))
            let slice = strip.width / CGFloat(curve.count)
            for index in curve.indices {
                let zone = HeartRateCurve.zone(curve[index], maxHR: maxHR)
                stripContext.fill(Path(CGRect(x: strip.minX + slice * CGFloat(index), y: strip.minY, width: slice + 0.8, height: strip.height)),
                                  with: .color(theme.zones[zone]))
            }

            // Time along the bottom.
            if showAxis, let minutes, minutes > 0 {
                let step: Double = minutes > 90 ? 30 : minutes > 40 ? 15 : minutes > 15 ? 5 : 2
                var mark = 0.0
                while mark <= minutes + 0.1 {
                    let label = mark == 0 ? "0" : (mark >= 60 ? String(format: "%d:%02d", Int(mark) / 60, Int(mark) % 60) : "\(Int(mark))′")
                    context.draw(Text(label).font(.system(size: 20, design: .monospaced)).foregroundColor(theme.tertiary),
                                 at: CGPoint(x: min(max(x(mark / minutes), 14), plot.maxX - 14), y: strip.maxY + axisRoom / 2 + 2))
                    mark += step
                }
            }
        }
    }
}

