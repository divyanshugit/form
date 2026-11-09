import SwiftUI
import UIKit

/// WHOOP-style zone colours, Z0 → Z5.
enum ZoneColors {
    static let all: [Color] = [
        Color(hex: 0xE4E4E6), Color(hex: 0xA9B6C6), Color(hex: 0x4F8FD0),
        Color(hex: 0x5DBB8A), Color(hex: 0xF0A95A), Color(hex: 0xE8642E),
    ]
}

/// Story geometry shared by every layout.
enum CardMetrics {
    /// Drawn at 1080 × 1920 points and rendered at scale 1: an Instagram story.
    static let size = CGSize(width: 1080, height: 1920)
    /// Margins around the content.
    static let insets = EdgeInsets(top: 120, leading: 76, bottom: 76, trailing: 76)
}

extension View {
    /// Pins a view to the story size and clips anything outside it.
    func storyFrame(alignment: Alignment = .center) -> some View {
        frame(width: CardMetrics.size.width, height: CardMetrics.size.height, alignment: alignment).clipped()
    }
}

/// A colour composition for the story card: background, type, one accent, and the six zone colours.
struct CardTheme: Sendable {
    var bg: Color
    var text: Color
    var accent: Color
    var zones: [Color]

    /// WHOOP's own colours on navy: what the app's other screens use.
    /// Type levels: body copy, labels and captions, rules and dividers.
    var secondary: Color { text.opacity(0.85) }
    var tertiary: Color { text.opacity(0.6) }
    var hairline: Color { text.opacity(0.18) }

    static let whoop = CardTheme(bg: Color(hex: 0x0E1A33), text: .white, accent: Palette.orange, zones: ZoneColors.all)

    /// WHOOP's zone hues tuned for a near-black card: quiet greys at rest, then blue → green → amber → red.
    static let refinedZones: [Color] = [0x4A4A4E, 0x7D8A99, 0x4F8FD0, 0x5DBB8A, 0xF0B04E, 0xE8553F].map { Color(hex: $0) }

    private static func composition(bg: UInt32, text: UInt32, accent: UInt32) -> CardTheme {
        CardTheme(bg: Color(hex: bg), text: Color(hex: text), accent: Color(hex: accent), zones: refinedZones)
    }

    static let graphite = composition(bg: 0x111317, text: 0xE9EBEE, accent: 0xFF5A36)
    static let obsidian = composition(bg: 0x0E0E0F, text: 0xECE7DF, accent: 0xC8A97E)
    static let espresso = composition(bg: 0x16110E, text: 0xEFE6DA, accent: 0xC9774A)

    /// Over a photo the type goes white on a black base; accent and zones stay.
    func over(_ photo: UIImage?) -> CardTheme {
        guard photo != nil else { return self }
        var theme = self
        theme.text = .white
        theme.bg = .black
        return theme
    }

    /// The zone colours stacked by heart rate, from `bottom` (the low end of `range`) to `top`.
    /// Each zone holds its colour across its band and blends into the next over a few bpm, so a
    /// line stroked with it changes colour exactly where it crosses a zone, smoothly.
    func zoneShading(maxHR: Double, range: ClosedRange<Double>, bottom: CGFloat, top: CGFloat) -> GraphicsContext.Shading {
        let span = range.upperBound - range.lowerBound, blend = 2.5
        func location(_ bpm: Double) -> CGFloat { CGFloat(min(1, max(0, (bpm - range.lowerBound) / span))) }
        var stops: [Gradient.Stop] = []
        for zone in zones.indices {
            let lower = zone == 0 ? range.lowerBound : HeartRateCurve.zoneFloors[zone] * maxHR
            let upper = zone == zones.count - 1 ? range.upperBound : HeartRateCurve.zoneFloors[zone + 1] * maxHR
            stops.append(.init(color: zones[zone], location: location(lower + blend)))
            stops.append(.init(color: zones[zone], location: location(upper - blend)))
        }
        return .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: bottom), endPoint: CGPoint(x: 0, y: top))
    }
}

/// The colour compositions offered on the card.
enum CardPalette: String, CaseIterable, Identifiable {
    case graphite, obsidian, espresso

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var theme: CardTheme {
        switch self {
        case .graphite: .graphite
        case .obsidian: .obsidian
        case .espresso: .espresso
        }
    }
}

/// The background of a card without a photo.
enum PlainBackground: String, CaseIterable, Identifiable {
    case washGrid, grid, accentWash

    var id: String { rawValue }
    var name: String {
        switch self {
        case .washGrid: "Wash + grid"
        case .grid: "Grid"
        case .accentWash: "Wash"
        }
    }
}

private struct CardThemeKey: EnvironmentKey {
    static let defaultValue = CardTheme.whoop
}

private struct PlainBackgroundKey: EnvironmentKey {
    static let defaultValue = PlainBackground.washGrid
}

extension EnvironmentValues {
    var cardTheme: CardTheme {
        get { self[CardThemeKey.self] }
        set { self[CardThemeKey.self] = newValue }
    }

    /// The background for cards without a photo.
    var plainBackground: PlainBackground {
        get { self[PlainBackgroundKey.self] }
        set { self[PlainBackgroundKey.self] = newValue }
    }
}

/// Type styles for the story card. Bundled OFL fonts (Form/Resources/Fonts), with fixed sizes so the
/// 1080 × 1920 render never follows Dynamic Type.
enum CardFont: String, CaseIterable, Identifiable {
    /// Editorial matches divyanshugit.github.io: Instrument Serif for display, Raleway for text.
    case editorial, poster, wide, technical

    var id: String { rawValue }

    var name: String {
        switch self {
        case .poster: "Poster"
        case .wide: "Wide"
        case .editorial: "Editorial"
        case .technical: "Technical"
        }
    }

    private func custom(_ name: String, _ size: CGFloat) -> Font {
        // Raleway defaults to old-style figures ("Z0" reads as "Zo"); data wants lining ones.
        guard name.hasPrefix("Raleway"), let base = UIFont(name: name, size: size) else { return .custom(name, fixedSize: size) }
        let lining: [UIFontDescriptor.FeatureKey: Int] = [.type: kNumberCaseType, .selector: kUpperCaseNumbersSelector]
        return Font(UIFont(descriptor: base.fontDescriptor.addingAttributes([.featureSettings: [lining]]), size: size))
    }

    /// The headline.
    func title(_ size: CGFloat) -> Font {
        switch self {
        case .poster: custom("Anton-Regular", size * 1.05)
        case .wide: custom("Unbounded-ExtraBold", size * 0.62)
        case .editorial: custom("InstrumentSerif-Regular", size * 1.15)
        case .technical: custom("SpaceGrotesk-Bold", size * 0.88)
        }
    }

    /// The hero number and banners.
    func display(_ size: CGFloat) -> Font {
        switch self {
        case .poster: custom("Anton-Regular", size * 1.12)
        case .wide: custom("Unbounded-ExtraBold", size * 0.7)
        case .editorial: custom("InstrumentSerif-Regular", size * 1.12)
        case .technical: custom("SpaceGrotesk-Bold", size * 0.9)
        }
    }

    /// Stat values.
    func number(_ size: CGFloat) -> Font {
        switch self {
        case .poster: custom("Anton-Regular", size * 1.08)
        case .wide: custom("Unbounded-Medium", size * 0.78)
        case .editorial: custom("InstrumentSerif-Regular", size * 1.2)
        case .technical: custom("JetBrainsMono-Bold", size * 0.88)
        }
    }

    /// Labels and body text.
    func body(_ size: CGFloat) -> Font {
        switch self {
        case .poster: .system(size: size, weight: .semibold).width(.condensed)
        case .wide: .system(size: size, weight: .medium)
        case .editorial: custom("Raleway-Medium", size)
        case .technical: custom("SpaceGrotesk-Medium", size)
        }
    }

    /// The line under the headline: serif on Editorial, like the site's tagline.
    func subtitle(_ size: CGFloat) -> Font {
        self == .editorial ? custom("InstrumentSerif-Regular", size * 1.3) : body(size)
    }

    /// The date line above a single session.
    func eyebrow(_ size: CGFloat) -> Font {
        self == .editorial ? custom("InstrumentSerif-Italic", size * 1.5) : caps(size)
    }

    /// Small caps labels.
    func caps(_ size: CGFloat) -> Font {
        switch self {
        case .technical: custom("JetBrainsMono-Medium", size)
        case .poster: .system(size: size, weight: .bold).width(.condensed)
        case .editorial: custom("Raleway-Bold", size)
        default: .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}

