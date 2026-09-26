import SwiftUI

/// The progression strip: 2–4 photos side by side at the same height, optional date and weight
/// labels, rendered to a single image to save or share.
struct CollageView: View {
    @Environment(PhotoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let photos: [ProgressPhoto]

    @State private var images: [UIImage] = []
    @State private var showLabels = true
    @State private var rendered: UIImage?

    private func renderCollage() {
        guard images.count == photos.count else { return }
        rendered = CollageRenderer.render(images: images, photos: photos, labels: showLabels, dayNumber: store.dayNumber)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Collage of \(photos.count) progress photos")
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                }

                Toggle("Date & weight labels", isOn: $showLabels)
                    .tint(Palette.denim)
                    .padding(14)
                    .card()

                if let first = photos.first, let last = photos.last {
                    Text(PhotoTimeline.change(from: first, to: last))
                        .font(.headline)
                        .foregroundStyle(Palette.slateText)
                }
                Spacer()

                if let rendered {
                    ShareLink(item: Image(uiImage: rendered),
                              preview: SharePreview("Progress", image: Image(uiImage: rendered))) {
                        Label("Save or share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryKeyStyle(height: 60))
                }
            }
            .padding(16)
            .background(Palette.bone)
            .navigationTitle("Collage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                var loaded: [UIImage] = []
                for photo in photos {
                    if let image = await store.image(for: photo) { loaded.append(image) }
                }
                images = loaded
                renderCollage()
            }
            .onChange(of: showLabels) { renderCollage() }
        }
    }
}

enum CollageRenderer {
    /// Draws the photos as equal-width 3:4 panels with a thin gap, like a mirror-selfie triptych.
    @MainActor
    static func render(images: [UIImage], photos: [ProgressPhoto], labels: Bool,
                       dayNumber: (ProgressPhoto) -> Int) -> UIImage {
        let panel = CGSize(width: 900, height: 1200)
        let gap: CGFloat = 8
        let count = CGFloat(max(1, images.count))
        let size = CGSize(width: panel.width * count + gap * (count - 1), height: panel.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(hex: 0x0E1A33).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, image) in images.enumerated() {
                let rect = CGRect(x: CGFloat(index) * (panel.width + gap), y: 0, width: panel.width, height: panel.height)
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect)
                image.draw(in: aspectFill(image.size, in: rect))
                context.cgContext.restoreGState()

                guard labels, index < photos.count else { continue }
                let photo = photos[index]
                let title = "DAY \(dayNumber(photo))"
                let subtitle = [photo.takenAt.formatted(.dateTime.day().month(.abbreviated).year()),
                                photo.bodyWeightKg.map { "\($0.kg) kg" }].compactMap { $0 }.joined(separator: " · ")
                let band = CGRect(x: rect.minX, y: rect.maxY - 200, width: rect.width, height: 200)
                UIColor.black.withAlphaComponent(0.5).setFill()
                context.fill(band)
                let titleFont = UIFont.systemFont(ofSize: 80, weight: .heavy).expanded
                (title as NSString).draw(at: CGPoint(x: band.minX + 40, y: band.minY + 20),
                                         withAttributes: [.font: titleFont, .foregroundColor: UIColor.white])
                (subtitle as NSString).draw(at: CGPoint(x: band.minX + 42, y: band.minY + 122),
                                            withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 46, weight: .semibold),
                                                             .foregroundColor: UIColor(white: 0.9, alpha: 1)])
            }
        }
    }

    private static func aspectFill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}

private extension UIFont {
    var expanded: UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.width: 0.3]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
