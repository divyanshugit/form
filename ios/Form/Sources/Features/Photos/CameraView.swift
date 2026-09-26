import AVFoundation
import PhotosUI
import SwiftUI

/// Progress-photo camera. Your last photo sits over the viewfinder as a ghost, so every shot
/// lines up: same spot, same pose, same distance.
struct CameraView: View {
    @Environment(PhotoStore.self) private var photos
    @Environment(\.dismiss) private var dismiss
    var workoutID: UUID? = nil

    @State private var camera = CameraModel()
    @State private var ghost: UIImage?
    @State private var ghostOpacity = 0.3
    @State private var timerSeconds = 0
    @State private var countdown: Int?
    @State private var captured: UIImage?
    @State private var capturedDate = Date.now
    @State private var weightText = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Palette.midnight.ignoresSafeArea()
            if let captured {
                review(captured)
            } else {
                viewfinder
            }
        }
        .task {
            await camera.start()
            if let latest = photos.latest { ghost = await photos.image(for: latest) }
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        VStack(spacing: 0) {
            HStack {
                circleButton("xmark", label: "Close") { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    Text("Progress photo").font(.headline).foregroundStyle(Palette.chalk)
                    if let latest = photos.latest {
                        Text("Matching \(latest.takenAt.formatted(.dateTime.day().month(.abbreviated)))")
                            .labelStyle(Palette.chalk.opacity(0.7))
                    }
                }
                Spacer()
                circleButton("arrow.triangle.2.circlepath.camera", label: "Switch camera") {
                    Task { await camera.flip() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ZStack {
                switch camera.status {
                case .running:
                    CameraPreview(session: camera.session, mirrored: camera.position == .front)
                case .denied:
                    placeholder("Camera access is off. Turn it on in Settings → Form, or import from Photos below.")
                case .unavailable:
                    placeholder("No camera here. Import a photo from your library instead.")
                case .idle:
                    ProgressView().tint(Palette.chalk)
                }
                if let ghost, ghostOpacity > 0, camera.status == .running {
                    Image(uiImage: ghost)
                        .resizable()
                        .scaledToFill()
                        .opacity(ghostOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let countdown {
                    Text("\(countdown)")
                        .font(.cast(120))
                        .foregroundStyle(Palette.chalk)
                        .shadow(radius: 12)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 8)

            if ghost != nil {
                Picker("Ghost", selection: $ghostOpacity) {
                    Text("Off").tag(0.0)
                    Text("20%").tag(0.2)
                    Text("30%").tag(0.3)
                    Text("50%").tag(0.5)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)
                .padding(.top, 14)
                .accessibilityLabel("Ghost overlay opacity")
            }

            Spacer()

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(Palette.chalk)
                        .frame(width: 52, height: 52)
                        .background(Palette.chalk.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Import from Photos")

                Spacer()

                Button {
                    Task { await shoot() }
                } label: {
                    Circle()
                        .strokeBorder(Palette.chalk, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .overlay(Circle().fill(Palette.orange).padding(8))
                }
                .disabled(camera.status != .running || countdown != nil)
                .accessibilityLabel("Take photo")

                Spacer()

                Button {
                    timerSeconds = [0, 3, 5, 10][([0, 3, 5, 10].firstIndex(of: timerSeconds)! + 1) % 4]
                } label: {
                    Text(timerSeconds == 0 ? "Off" : "\(timerSeconds)s")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(timerSeconds == 0 ? Palette.chalk : Palette.inkFixed)
                        .frame(width: 52, height: 52)
                        .background(timerSeconds == 0 ? Palette.chalk.opacity(0.12) : Palette.orange, in: Circle())
                }
                .accessibilityLabel("Self-timer, \(timerSeconds == 0 ? "off" : "\(timerSeconds) seconds")")
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
    }

    // MARK: Review

    private func review(_ image: UIImage) -> some View {
        VStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Day \(PhotoTimeline.dayNumber(of: ProgressPhoto(id: UUID(), storagePath: "", takenAt: capturedDate), first: photos.first?.takenAt ?? capturedDate)) · \(capturedDate.formatted(date: .abbreviated, time: .omitted))")
                    .labelStyle(Palette.chalk.opacity(0.8))
                HStack {
                    Text("Body weight").foregroundStyle(Palette.chalk)
                    Spacer()
                    TextField("optional", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Palette.chalk)
                        .frame(width: 100)
                    Text("kg").foregroundStyle(Palette.chalk.opacity(0.7))
                }
                .padding(14)
                .background(Palette.chalk.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 12) {
                Button("Retake") {
                    captured = nil
                }
                .buttonStyle(RestKeyStyle())

                Button {
                    Task { await save(image) }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save photo") }
                }
                .buttonStyle(RestKeyStyle(filled: true))
                .disabled(isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: Actions

    private func shoot() async {
        if timerSeconds > 0 {
            for remaining in stride(from: timerSeconds, to: 0, by: -1) {
                withAnimation { countdown = remaining }
                try? await Task.sleep(for: .seconds(1))
            }
            countdown = nil
        }
        if let image = await camera.capture() {
            capturedDate = .now
            captured = image
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        capturedDate = PhotoStore.captureDate(from: data) ?? .now
        captured = image
        pickerItem = nil
    }

    private func save(_ image: UIImage) async {
        isSaving = true
        let weight = Double(weightText.replacingOccurrences(of: ",", with: "."))
        await photos.add(image, takenAt: capturedDate, workoutID: workoutID, bodyWeightKg: weight)
        isSaving = false
        dismiss()
    }

    private func circleButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Palette.chalk)
                .frame(width: 44, height: 44)
                .background(Palette.chalk.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.chalk.opacity(0.8))
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.navy)
    }
}

/// AVCaptureVideoPreviewLayer in SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
}
