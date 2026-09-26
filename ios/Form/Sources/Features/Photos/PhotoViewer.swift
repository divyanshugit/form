import SwiftUI

/// Full-screen photo pager with day, date and weight. Swipe between photos; edit weight, share, delete.
struct PhotoViewer: View {
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    let start: ProgressPhoto

    @State private var current: UUID?
    @State private var confirmDelete = false
    @State private var editingWeight = false
    @State private var weightText = ""

    private var currentPhoto: ProgressPhoto? {
        photos.photos.first { $0.id == current }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(photos.photos) { photo in
                    FullPhoto(photo: photo)
                        .tag(Optional(photo.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Palette.midnight.ignoresSafeArea())
            .toolbarBackground(Palette.midnight, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if let photo = currentPhoto {
                        VStack(spacing: 0) {
                            Text("Day \(photos.dayNumber(photo))").font(.headline)
                            Text(photo.takenAt.formatted(date: .abbreviated, time: .omitted)
                                 + (photo.bodyWeightKg.map { " · \($0.kg) kg" } ?? ""))
                                .font(.caption)
                        }
                        .foregroundStyle(Palette.chalk)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Weight", systemImage: "scalemass") {
                        weightText = currentPhoto?.bodyWeightKg.map { $0.kg } ?? ""
                        editingWeight = true
                    }
                    Spacer()
                    if let photo = currentPhoto {
                        ShareablePhotoButton(photo: photo)
                    }
                    Spacer()
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    guard let photo = currentPhoto else { return }
                    Task {
                        await photos.delete(photo)
                        if photos.photos.isEmpty { dismiss() } else { current = photos.photos.first?.id }
                    }
                }
            }
            .alert("Body weight", isPresented: $editingWeight) {
                TextField("kg", text: $weightText).keyboardType(.decimalPad)
                Button("Save") {
                    guard let photo = currentPhoto else { return }
                    let kg = Double(weightText.replacingOccurrences(of: ",", with: "."))
                    Task { await photos.updateWeight(photo, kg: kg) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onAppear { current = start.id }
    }
}

private struct FullPhoto: View {
    @Environment(PhotoStore.self) private var store
    let photo: ProgressPhoto
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(Palette.chalk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.id) { image = await store.image(for: photo) }
    }
}

/// Loads the full image, then offers the system share sheet (save to Photos, AirDrop, Messages).
struct ShareablePhotoButton: View {
    @Environment(PhotoStore.self) private var store
    let photo: ProgressPhoto
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Progress photo", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Share", systemImage: "square.and.arrow.up").opacity(0.4)
            }
        }
        .task(id: photo.id) { image = await store.image(for: photo) }
    }
}
