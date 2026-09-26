import SwiftUI

/// Every progress photo, month by month. Select two to compare, or two to four for a collage.
struct PhotosView: View {
    @Environment(PhotoStore.self) private var photos

    enum Mode: Equatable { case browse, compare, collage }

    @State private var mode: Mode = .browse
    @State private var selection: [ProgressPhoto] = []
    @State private var showingCamera = false
    @State private var viewing: ProgressPhoto?
    @State private var comparing: ComparePair?
    @State private var collage: CollageSelection?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if photos.photos.isEmpty {
                        emptyState
                    } else {
                        if mode == .browse { shortcuts }
                        if mode != .browse { selectionBanner }
                        ForEach(PhotoTimeline.byMonth(photos.photos), id: \.month) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.month.formatted(.dateTime.month(.wide).year()))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Palette.ink)
                                LazyVGrid(columns: columns, spacing: 3) {
                                    ForEach(group.photos) { photo in
                                        Button {
                                            tap(photo)
                                        } label: {
                                            PhotoTile(photo: photo, day: photos.dayNumber(photo),
                                                      badge: selection.firstIndex(of: photo).map { $0 + 1 })
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    if photos.pendingCount > 0 {
                        Label("\(photos.pendingCount) waiting to upload", systemImage: "icloud.and.arrow.up")
                            .font(.footnote)
                            .foregroundStyle(Palette.slateText)
                    }
                    if let message = photos.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(Palette.slateText)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.bone)
            .navigationTitle("Photos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCamera = true
                    } label: {
                        Image(systemName: "camera.fill")
                    }
                    .accessibilityLabel("New progress photo")
                }
            }
            .refreshable { await photos.refresh() }
            .task {
                await photos.refresh()
                #if DEBUG
                if DemoMode.opensCollage, photos.photos.count >= 3 {
                    let sorted = photos.photos.sorted { $0.takenAt < $1.takenAt }
                    collage = CollageSelection(photos: [sorted[0], sorted[sorted.count / 2], sorted[sorted.count - 1]])
                }
                #endif
            }
            .fullScreenCover(isPresented: $showingCamera) { CameraView() }
            .fullScreenCover(item: $viewing) { PhotoViewer(start: $0) }
            .sheet(item: $comparing) { CompareView(older: $0.older, newer: $0.newer) }
            .sheet(item: $collage) { CollageView(photos: $0.photos) }
        }
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Day one starts here.").font(.cast(.title)).foregroundStyle(Palette.ink)
            Text("Same spot, same pose, same light. After the first photo, the camera shows it as a ghost so every photo after lines up.")
                .foregroundStyle(Palette.slateText)
            Button {
                showingCamera = true
            } label: {
                Label("Take the first photo", systemImage: "camera.fill")
            }
            .buttonStyle(PrimaryKeyStyle())
        }
        .padding(.top, 32)
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            shortcut("Compare", systemImage: "rectangle.split.2x1") {
                selection = []
                mode = .compare
            }
            shortcut("Collage", systemImage: "rectangle.split.3x1") {
                selection = []
                mode = .collage
            }
            if let first = photos.first, let latest = photos.latest, first != latest {
                shortcut("Day 1 vs now", systemImage: "arrow.left.and.right") {
                    comparing = ComparePair(older: first, newer: latest)
                }
            }
        }
    }

    private func shortcut(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Palette.denim)
    }

    private var selectionBanner: some View {
        let needed = mode == .compare ? "Pick 2 photos" : "Pick 2 to 4 photos"
        let ready = mode == .compare ? selection.count == 2 : (2...4).contains(selection.count)
        return HStack {
            Text("\(needed) · \(selection.count) selected").labelStyle(Palette.ink)
            Spacer()
            Button("Cancel") {
                mode = .browse
                selection = []
            }
            Button(mode == .compare ? "Compare" : "Make collage") {
                let ordered = selection.sorted { $0.takenAt < $1.takenAt }
                if mode == .compare {
                    comparing = ComparePair(older: ordered[0], newer: ordered[1])
                } else {
                    collage = CollageSelection(photos: ordered)
                }
                mode = .browse
                selection = []
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.orange)
            .foregroundStyle(Palette.inkFixed)
            .disabled(!ready)
        }
        .padding(12)
        .card()
    }

    private func tap(_ photo: ProgressPhoto) {
        switch mode {
        case .browse:
            viewing = photo
        case .compare, .collage:
            if let index = selection.firstIndex(of: photo) {
                selection.remove(at: index)
            } else if selection.count < (mode == .compare ? 2 : 4) {
                selection.append(photo)
            }
        }
    }
}

struct ComparePair: Identifiable {
    var id: String { older.id.uuidString + newer.id.uuidString }
    let older: ProgressPhoto
    let newer: ProgressPhoto
}

struct CollageSelection: Identifiable {
    let id = UUID()
    let photos: [ProgressPhoto]
}

/// 3:4 thumbnail with day number, weight tag and an optional orange selection badge.
struct PhotoTile: View {
    @Environment(PhotoStore.self) private var store
    let photo: ProgressPhoto
    let day: Int
    var badge: Int? = nil

    @State private var image: UIImage?

    var body: some View {
        Color(Palette.navy)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().tint(Palette.chalk)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DAY \(day)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                    if let kg = photo.bodyWeightKg {
                        Text("\(kg.kg) kg").font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundStyle(Palette.chalk)
                .padding(6)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text("\(badge)")
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(Palette.inkFixed)
                        .frame(width: 28, height: 28)
                        .background(Palette.orange, in: Circle())
                        .padding(6)
                }
            }
            .overlay {
                if badge != nil { Rectangle().strokeBorder(Palette.orange, lineWidth: 3) }
            }
            .task(id: photo.id) { image = await store.thumbnail(for: photo) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Day \(day), \(photo.takenAt.formatted(date: .abbreviated, time: .omitted))\(photo.bodyWeightKg.map { ", \($0.kg) kilograms" } ?? "")")
            .accessibilityAddTraits(badge != nil ? [.isButton, .isSelected] : .isButton)
    }
}
