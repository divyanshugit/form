import SwiftUI

/// The three story layouts the share sheet offers.
enum CardLayout: String, CaseIterable, Identifiable {
    /// Hero number, the heart-rate graph, the numbers. Also the only layout for weeks, recaps and milestones.
    case current
    /// A results sheet: highlight, time, three numbers, the graph, then splits or lifts.
    case ledger
    /// Heart rate around a clock face.
    case dial

    var id: String { rawValue }
    var name: String {
        switch self {
        case .current: "Classic"
        case .ledger: "Ledger"
        case .dial: "Dial"
        }
    }

    /// Ledger and Dial are single-session designs; the Dial needs a heart-rate curve.
    func available(for model: ShareCardModel) -> Bool {
        guard self != .current else { return true }
        guard model.banner == nil, model.sections.count == 1 else { return false }
        return self == .ledger || model.sections[0].curve != nil
    }

    func resolved(for model: ShareCardModel) -> CardLayout { available(for: model) ? self : .current }
}

/// The card as shared: the chosen layout in the chosen colours and background.
struct ShareCard: View {
    let model: ShareCardModel
    var background: UIImage?
    var font: CardFont = .editorial
    var layout: CardLayout = .current
    var palette: CardPalette = .graphite
    var highlight: String?
    var plain: PlainBackground = .washGrid

    var body: some View {
        Group {
            switch layout.resolved(for: model) {
            case .current: ShareCardView(model: model, background: background, font: font)
            case .ledger: LedgerCard(model: model, background: background, font: font, highlight: highlight)
            case .dial: DialCard(model: model, background: background, font: font)
            }
        }
        .environment(\.cardTheme, palette.theme)
        .environment(\.plainBackground, plain)
    }
}
