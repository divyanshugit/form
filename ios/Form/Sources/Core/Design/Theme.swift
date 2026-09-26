import SwiftUI
import UIKit

/// Form palette: chalk & iron neutrals, muted navy/denim blues, one burnt-orange accent.
/// Every token has a dark-mode variant so the app follows the system appearance.
enum Palette {
    static let bone = dynamic(light: 0xEEE7DA, dark: 0x10151F)       // background
    static let card = dynamic(light: 0xF6F2EA, dark: 0x182131)       // raised surfaces
    static let fog = dynamic(light: 0xE6E4DD, dark: 0x1F2A3C)        // tinted panels
    static let rule = dynamic(light: 0xD8CFBE, dark: 0x2B3649)       // hairlines
    static let ink = dynamic(light: 0x16171A, dark: 0xF4EFE6)        // primary text
    static let slateText = dynamic(light: 0x45577A, dark: 0xA9B3BE)  // secondary text
    static let denim = dynamic(light: 0x2C4466, dark: 0x8FA8C8)      // blue accent / links

    static let navy = Color(hex: 0x1C2B45)       // dark hero surfaces
    static let midnight = Color(hex: 0x0E1A33)   // photo viewers
    static let chalk = Color(hex: 0xF4EFE6)      // text on navy
    static let orange = Color(hex: 0xE2632A)     // the one hot accent
    static let orangeShadow = Color(hex: 0xA8441A)
    static let inkFixed = Color(hex: 0x16171A)   // text on orange, in both modes

    // Plate colours
    static let slate = Color(hex: 0x5C6D82)
    static let mist = Color(hex: 0xC4CCD3)
    static let sand = Color(hex: 0xD8C9AA)
    static let chrome = Color(hex: 0xA3AAB3)
    static let denimFixed = Color(hex: 0x2C4466)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Type scale. "Cast" numerals mimic the lettering cast into iron plates (SF Pro, expanded, heavy).
extension Font {
    static func cast(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    static func cast(_ style: Font.TextStyle) -> Font {
        .system(style, weight: .heavy).width(.expanded)
    }

    /// Tiny technical caps labels.
    static let label = Font.system(.caption2, design: .monospaced).weight(.medium)
}

extension View {
    /// Monospaced caps label with tracking, used for section headers and metadata.
    func labelStyle(_ color: Color = Palette.slateText) -> some View {
        self.font(.label)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
