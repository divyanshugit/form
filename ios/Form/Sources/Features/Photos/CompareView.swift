import SwiftUI

/// Two dates, one frame. Drag the divider to wipe between then and now.
struct CompareView: View {
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    let older: ProgressPhoto
    let newer: ProgressPhoto

    @State private var olderImage: UIImage?
    @State private var newerImage: UIImage?
    @State private var split: CGFloat = 0.5
    @State private var sideBySide = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Layout", selection: $sideBySide) {
                    Text("Slider").tag(false)
                    Text("Side by side").tag(true)
                }
                .pickerStyle(.segmented)

                if sideBySide {
                    HStack(spacing: 3) {
                        labelled(olderImage, photo: older)
                        labelled(newerImage, photo: newer)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    slider
                }

                Text(PhotoTimeline.change(from: older, to: newer))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(16)
            .background(Palette.bone)
            .navigationTitle("Day \(photos.dayNumber(older)) vs Day \(photos.dayNumber(newer))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if let shareImage {
                        ShareLink(item: Image(uiImage: shareImage),
                                  preview: SharePreview("Then and now", image: Image(uiImage: shareImage))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                async let a = photos.image(for: older)
                async let b = photos.image(for: newer)
                (olderImage, newerImage) = await (a, b)
                if let olderImage, let newerImage {
                    shareImage = CollageRenderer.render(images: [olderImage, newerImage], photos: [older, newer],
                                                        labels: true, dayNumber: photos.dayNumber)
                }
            }
        }
    }

    private var slider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                photoLayer(newerImage)
                photoLayer(olderImage)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * split)
                    }
                Rectangle()
                    .fill(Palette.chalk)
                    .frame(width: 3)
                    .offset(x: geo.size.width * split - 1.5)
                Circle()
                    .fill(Palette.chalk)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.headline).foregroundStyle(Palette.inkFixed))
                    .shadow(radius: 4)
                    .offset(x: geo.size.width * split - 22)
                tag(older, alignment: .topLeading)
                tag(newer, alignment: .topTrailing)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / geo.size.width))
            })
            .accessibilityElement()
            .accessibilityLabel("Comparison slider")
            .accessibilityValue("\(Int(split * 100)) percent Day \(photos.dayNumber(older))")
            .accessibilityAdjustableAction { direction in
                split = min(1, max(0, split + (direction == .increment ? 0.1 : -0.1)))
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func photoLayer(_ image: UIImage?) -> some View {
        Color(Palette.navy).overlay {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .clipped()
    }

    private func tag(_ photo: ProgressPhoto, alignment: Alignment) -> some View {
        VStack(alignment: alignment == .topLeading ? .leading : .trailing, spacing: 0) {
            Text("DAY \(photos.dayNumber(photo))").font(.system(.caption, design: .monospaced).weight(.heavy))
            if let kg = photo.bodyWeightKg { Text("\(kg.kg) kg").font(.system(.caption2, design: .monospaced)) }
        }
        .foregroundStyle(Palette.chalk)
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private func labelled(_ image: UIImage?, photo: ProgressPhoto) -> some View {
        photoLayer(image)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay(alignment: .bottomLeading) { tag(photo, alignment: .bottomLeading) }
    }
}
