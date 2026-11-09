import SwiftUI

/// Heart rate around a clock face, on its own disc so it reads on any photo; the numbers sit below.
struct DialCard: View {
    @Environment(\.cardTheme) private var composition
    let model: ShareCardModel
    var background: UIImage?
    var font: CardFont

    private var section: ShareCardModel.Section { model.sections[0] }
    private var theme: CardTheme { composition.over(background) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            StoryBackground(image: background)
            VStack(alignment: .leading, spacing: 0) {
                CardEyebrow(section: section, font: font)
                Text(model.title).font(font.title(80)).foregroundStyle(theme.text).lineLimit(2).minimumScaleFactor(0.6)
                    .padding(.top, 14)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle).font(font.subtitle(30)).foregroundStyle(theme.secondary).padding(.top, 6)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(theme.bg.opacity(background == nil ? 0.92 : 0.55)).frame(width: 900, height: 900)
                        .overlay(Circle().stroke(theme.hairline, lineWidth: 2))
                        .shadow(color: .black.opacity(0.3), radius: 40)
                    DialChart(section: section, maxHR: model.maxHR)
                    VStack(spacing: 6) {
                        Text(section.hero).font(font.display(140)).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.5)
                        Text((section.heroCaption ?? "").uppercased()).font(font.caps(20)).tracking(3).foregroundStyle(theme.tertiary)
                    }
                    .frame(width: 460)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 920)
                Spacer(minLength: 0)
                CardStatRow(stats: section.cardStats, font: font)
                CardFooter(text: model.footer, font: font).padding(.top, 36)
            }
            .padding(CardMetrics.insets)
            .legible(onPhoto: background != nil)
        }
        .storyFrame()
        .environment(\.cardTheme, theme)
    }
}

/// Radial heart-rate bars around a clock face, starting at 12 o'clock.
struct DialChart: View {
    @Environment(\.cardTheme) private var theme
    let section: ShareCardModel.Section
    let maxHR: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let inner: CGFloat = 260, outer: CGFloat = 400
            func angle(_ share: Double) -> Double { -Double.pi / 2 + 2 * Double.pi * share }
            func at(_ share: Double, _ r: CGFloat) -> CGPoint {
                CGPoint(x: center.x + r * CGFloat(cos(angle(share))), y: center.y + r * CGFloat(sin(angle(share))))
            }
            if let minutes = ShareCardView.minutes(section) {
                for quarter in 0..<4 {
                    let share = Double(quarter) / 4
                    context.draw(Text(quarter == 0 ? "0" : "\(Int((minutes * share).rounded()))′").font(.system(size: 19, design: .monospaced))
                                    .foregroundColor(theme.tertiary), at: at(share, inner - 30))
                }
            }
            for segment in section.segments where segment.isStation {
                var arc = Path()
                arc.addArc(center: center, radius: outer + 20, startAngle: .radians(angle(segment.start)),
                           endAngle: .radians(angle(segment.end)), clockwise: false)
                context.stroke(arc, with: .color(theme.tertiary), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            guard let curve = section.curve, curve.count > 1 else { return }
            let range = HeartRateCurveView.range(for: [section], maxHR: maxHR)
            let width = 2 * CGFloat.pi * inner / CGFloat(curve.count) * 0.6
            for index in curve.indices {
                let share = Double(index) / Double(curve.count)
                let length = (outer - inner) * CGFloat((curve[index] - range.lowerBound) / (range.upperBound - range.lowerBound))
                var bar = Path()
                bar.move(to: at(share, inner))
                bar.addLine(to: at(share, inner + max(6, length)))
                context.stroke(bar, with: .color(theme.zones[HeartRateCurve.zone(curve[index], maxHR: maxHR)]),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            let peak = section.peakBpm ?? curve.max() ?? 0
            let share = section.peakAt ?? Double(curve.indices.max { curve[$0] < curve[$1] }!) / Double(curve.count)
            let dot = at(share, outer + 2)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18)), with: .color(theme.accent))
            context.draw(Text("MAX \(Int(peak.rounded()))").font(.system(size: 21, weight: .bold, design: .monospaced)).foregroundColor(theme.text),
                         at: at(share, outer + 48))
        }
    }
}
