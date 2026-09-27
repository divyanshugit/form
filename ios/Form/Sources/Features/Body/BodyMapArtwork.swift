import SwiftUI

/// Front and back anatomy artwork, parsed once from `body-map.json`.
/// Source: react-native-body-highlighter 3.2.0 (MIT, © 2022 ELABBASSI Hicham).
/// Coordinates: front occupies x 0…724, back x 724…1448; both are 1448 tall.
struct BodyMapArtwork {
    struct Region: Identifiable {
        let slug: String
        let path: Path
        var id: String { slug }
        var bodyPart: BodyPart? { BodyPart(mapSlug: slug) }
    }

    enum Side { case front, back }

    static let figureSize = CGSize(width: 724, height: 1448)

    let front: [Region]
    let back: [Region]
    let frontOutline: Path
    let backOutline: Path

    func regions(_ side: Side) -> [Region] { side == .front ? front : back }
    func outline(_ side: Side) -> Path { side == .front ? frontOutline : backOutline }
    /// X offset of the side's artwork inside the shared coordinate space.
    static func originX(_ side: Side) -> CGFloat { side == .front ? 0 : 724 }

    static let shared: BodyMapArtwork? = load()

    private struct File: Decodable {
        struct Entry: Decodable { let slug: String; let d: String }
        struct Outline: Decodable { let front: String; let back: String }
        let front: [Entry]
        let back: [Entry]
        let outline: Outline
    }

    static func load(bundle: Bundle = .main) -> BodyMapArtwork? {
        guard let url = bundle.url(forResource: "body-map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let map: ([File.Entry]) -> [Region] = { $0.map { Region(slug: $0.slug, path: SVGPath.parse($0.d)) } }
        return BodyMapArtwork(front: map(file.front), back: map(file.back),
                              frontOutline: SVGPath.parse(file.outline.front),
                              backOutline: SVGPath.parse(file.outline.back))
    }
}
