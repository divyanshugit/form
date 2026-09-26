@preconcurrency import AVFoundation
import UIKit

/// Minimal photo camera: back or front lens, capture to UIImage.
/// The session runs on its own queue; state the UI reads is published on the main actor.
@MainActor
@Observable
final class CameraModel: NSObject {
    enum Status { case idle, running, denied, unavailable }

    private(set) var status: Status = .idle
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isCapturing = false

    nonisolated let session = AVCaptureSession()
    nonisolated private let output = AVCapturePhotoOutput()
    nonisolated private let queue = DispatchQueue(label: "form.camera")
    private var continuation: CheckedContinuation<UIImage?, Never>?

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        case .denied, .restricted:
            status = .denied
            return
        default:
            break
        }
        let ok = await configure(position: position)
        status = ok ? .running : .unavailable
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }

    func flip() async {
        position = position == .back ? .front : .back
        _ = await configure(position: position)
    }

    func capture() async -> UIImage? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        let output = self.output
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            queue.async {
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configure(position: AVCaptureDevice.Position) async -> Bool {
        let session = self.session
        let output = self.output
        return await withCheckedContinuation { continuation in
            queue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo
                session.inputs.forEach { session.removeInput($0) }
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    session.addOutput(output)
                }
                output.maxPhotoQualityPrioritization = .quality
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            // Front-camera shots are mirrored so they match what you saw in the preview.
            let final = (self.position == .front) ? image?.mirrored() : image
            self.continuation?.resume(returning: final)
            self.continuation = nil
        }
    }
}

private extension UIImage {
    func mirrored() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            draw(at: .zero)
        }
    }
}
