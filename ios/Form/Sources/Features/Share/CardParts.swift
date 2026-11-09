import SwiftUI

/// Pieces every story layout shares: the background, the date line, the stat row, the footer.

extension ShareCardModel.Section {
    /// Up to four numbers for the stat row; the start time is already in the date line.
    var cardStats: [ShareCardModel.Stat] {
        Array((stats.filter { $0.label != "start" } + details).prefix(4))
    }
}

extension View {
    /// A soft shadow under the type when it sits on a photo; nothing on a plain background.
    func legible(onPhoto: Bool, radius: CGFloat = 6) -> some View {
        shadow(color: .black.opacity(onPhoto ? 0.45 : 0), radius: radius, y: 1)
    }
}

/// With a photo: the photo fills the card, shaded where the type sits.
/// Without one: the composition's background, as chosen in `plainBackground`.
struct StoryBackground: View {
    var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZStack {
                    Color.black
                    Image(uiImage: image).resizable().scaledToFill().storyFrame()
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.18),
                        .init(color: .black.opacity(0.15), location: 0.32), .init(color: .black.opacity(0.55), location: 0.58),
                        .init(color: .black.opacity(0.7), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            } else {
                PlainBackgroundView()
            }
        }
        .storyFrame()
    }
}

/// The composition's background with a wash of its accent from the top, chart-paper lines, or both.
struct PlainBackgroundView: View {
    @Environment(\.cardTheme) private var theme
    @Environment(\.plainBackground) private var style

    var body: some View {
        ZStack(alignment: .top) {
            theme.bg
            if style != .grid { wash }
            if style != .accentWash { grid.opacity(style == .washGrid ? 0.8 : 1) }
        }
        .storyFrame()
    }

    private var wash: some View {
        let strength = style == .accentWash ? 1.0 : 0.75
        return LinearGradient(stops: [.init(color: theme.accent.opacity(0.24 * strength), location: 0),
                                      .init(color: theme.accent.opacity(0.06 * strength), location: 0.29),
                                      .init(color: .clear, location: 0.49)], startPoint: .top, endPoint: .bottom)
    }

    /// Chart paper: a fine grid with a stronger line every fifth, fading out before the numbers.
    private var grid: some View {
        Canvas { context, size in
            let cell: CGFloat = 54, cellsPerMajor = 5
            var minor = Path(), major = Path()
            for (count, offset) in stride(from: CGFloat(0), through: size.width, by: cell).enumerated() {
                let line = Path { $0.move(to: CGPoint(x: offset, y: 0)); $0.addLine(to: CGPoint(x: offset, y: size.height)) }
                count % cellsPerMajor == 0 ? major.addPath(line) : minor.addPath(line)
            }
            for (count, offset) in stride(from: CGFloat(0), through: size.height, by: cell).enumerated() {
                let line = Path { $0.move(to: CGPoint(x: 0, y: offset)); $0.addLine(to: CGPoint(x: size.width, y: offset)) }
                count % cellsPerMajor == 0 ? major.addPath(line) : minor.addPath(line)
            }
            // Fainter than a hairline: the paper should read as texture, not as a chart.
            context.stroke(minor, with: .color(theme.hairline.opacity(0.25)), lineWidth: 1)
            context.stroke(major, with: .color(theme.hairline.opacity(0.5)), lineWidth: 1.5)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.22),
                                     .init(color: .clear, location: 0.42)], startPoint: .top, endPoint: .bottom))
    }
}

/// The session's date and time above the title.
struct CardEyebrow: View {
    @Environment(\.cardTheme) private var theme
    let section: ShareCardModel.Section
    var font: CardFont
    /// Serif italic on Editorial (Classic); small caps otherwise.
    var italic = false

    var body: some View {
        if let start = section.start {
            let text = ShareCardView.eyebrow(start, end: section.end)
            Text(italic && font == .editorial ? text.capitalized : text)
                .font(italic ? font.eyebrow(24) : font.caps(24))
                .tracking(italic && font == .editorial ? 0.5 : 3)
                .foregroundStyle(theme.secondary)
        }
    }
}

/// Up to four numbers in columns, split by hairlines.
struct CardStatRow: View {
    @Environment(\.cardTheme) private var theme
    let stats: [ShareCardModel.Stat]
    var font: CardFont

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                HStack(spacing: 0) {
                    if index > 0 {
                        Rectangle().fill(theme.hairline).frame(width: 1.5, height: 86).padding(.trailing, 28)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(stat.value).font(font.number(52)).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.6)
                        Text(stat.label).font(font.caps(20)).tracking(2).textCase(.uppercase).foregroundStyle(theme.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// "form · day 43", bottom right.
struct CardFooter: View {
    @Environment(\.cardTheme) private var theme
    let text: String
    var font: CardFont

    var body: some View {
        HStack {
            Spacer()
            Text(text).font(font.caps(22)).tracking(3).textCase(.uppercase).foregroundStyle(theme.tertiary)
        }
    }
}

extension Path {
    /// A smooth curve through points, rounding each corner at the midpoint between samples.
    static func smoothed(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (previous, current) in zip(points, points.dropFirst()) {
            path.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2), control: previous)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}

extension HyroxStation {
    /// The station's name on a card row, from its timeline label.
    static func cardName(_ short: String) -> String {
        switch short {
        case "BBJ": "Burpees"
        case "CARRY": "Farmers"
        case "LUNGE": "Lunges"
        default: allCases.first { $0.short == short }?.title ?? short
        }
    }
}
