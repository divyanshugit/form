import SwiftUI

/// One side of the body, muscles tinted by how recently they were trained.
/// Decorative for VoiceOver: the body-part list next to it is the accessible control.
struct MuscleMapView: View {
    let side: BodyMapArtwork.Side
    let freshness: [BodyPart: Freshness]
    var highlighted: BodyPart? = nil
    var onTap: ((BodyPart) -> Void)? = nil

    var body: some View {
        if let art = BodyMapArtwork.shared {
            ZStack {
                ForEach(art.regions(side)) { region in
                    let shape = FittedPath(path: region.path, originX: BodyMapArtwork.originX(side))
                    if let part = region.bodyPart {
                        shape
                            .fill(fill(for: part))
                            .overlay(shape.stroke(part == highlighted ? Palette.ink : Palette.rule,
                                                  lineWidth: part == highlighted ? 1.8 : 0.6))
                            .onTapGesture { onTap?(part) }
                    } else {
                        shape
                            .fill(region.slug == "hair" ? Palette.rule : Palette.fog)
                            .overlay(shape.stroke(Palette.rule, lineWidth: 0.6))
                            .allowsHitTesting(false)
                    }
                }
                FittedPath(path: art.outline(side), originX: BodyMapArtwork.originX(side))
                    .stroke(Palette.rule, lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .aspectRatio(BodyMapArtwork.figureSize.width / BodyMapArtwork.figureSize.height, contentMode: .fit)
            .accessibilityHidden(true)
        }
    }

    private func fill(for part: BodyPart) -> Color {
        switch freshness[part] ?? .stale {
        case .fresh: Palette.orange
        case .recent: Palette.orange.opacity(0.45)
        case .stale: Palette.rule.opacity(0.7)
        }
    }
}

/// Scales artwork from its 724×1448 space into the view's rect.
private struct FittedPath: Shape {
    let path: Path
    let originX: CGFloat

    func path(in rect: CGRect) -> Path {
        let size = BodyMapArtwork.figureSize
        let scale = min(rect.width / size.width, rect.height / size.height)
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -originX, y: 0)
        return path.applying(transform)
    }
}

/// Legend swatches for the three freshness levels.
struct FreshnessLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(Palette.orange, "Last 2 days")
            item(Palette.orange.opacity(0.45), "3–5 days")
            item(Palette.rule.opacity(0.7), "6+ days")
        }
        .font(.caption)
        .foregroundStyle(Palette.slateText)
        .accessibilityElement(children: .combine)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
        }
    }
}
