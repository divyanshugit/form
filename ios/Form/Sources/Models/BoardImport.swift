import Foundation
import ImageIO
import UIKit

/// Backfilling class sessions from whiteboard photos: when the photo was taken, which logged session it
/// belongs to, and the planned sets each scanned line becomes.
enum BoardImport {
    // MARK: Photo

    /// When the photo was taken, from its EXIF (with the camera's UTC offset when present).
    static func takenAt(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return exifDate(stamp, offset: exif["OffsetTimeOriginal" as CFString] as? String)
    }

    /// "2026:11:04 15:53:43" + "+08:00".
    static func exifDate(_ stamp: String, offset: String?, fallback: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: stamp + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = fallback
        return formatter.date(from: stamp)
    }

    /// A downsampled, upright image for text recognition. ProRAW DNGs are 50–65 MB; this keeps memory flat.
    static func image(_ data: Data, maxPixel: Int = 3000) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }

    // MARK: Matching

    private static let lowEffort: Set<String> = ["Walking", "Activity"]

    /// The session a board photo belongs to. Boards are photographed just before or during class, so the
    /// photo should fall between 60 minutes before the start and the end. Sessions with no exercises yet,
    /// then real workouts over walks, then the closest start win.
    static func session(for takenAt: Date, in history: [WorkoutRow]) -> WorkoutRow? {
        history
            .filter { workout in
                let end = workout.endedAt ?? workout.startedAt.addingTimeInterval(3600)
                return takenAt >= workout.startedAt.addingTimeInterval(-3600) && takenAt <= end
            }
            .min { a, b in
                rank(a, takenAt) < rank(b, takenAt)
            }
    }

    private static func rank(_ workout: WorkoutRow, _ takenAt: Date) -> (Int, Int, Double) {
        (workout.sortedExercises.isEmpty ? 0 : 1,
         lowEffort.contains(workout.name) ? 1 : 0,
         abs(workout.startedAt.timeIntervalSince(takenAt)))
    }

    // MARK: Planned sets

    /// Sets for an exercise read off a board, logged at the session's start (it already happened).
    /// `weights` are the starting weights per set (e.g. last time's); without them, weighted sets start at
    /// 0 kg so a backfilled session never claims a weight nobody lifted.
    static func plannedExercise(_ exercise: Exercise, sets setCount: Int, reps: Int?, seconds: Int?, note: String?,
                                at start: Date, weights: [Double] = []) -> DraftExercise {
        let count = max(1, setCount)
        let sets = (0..<count).map { i -> DraftSet in
            let weight = weights.isEmpty ? 0 : weights[min(i, weights.count - 1)]
            switch exercise.metric {
            case .duration:
                return DraftSet(weight: weight, reps: 0, completedAt: start, durationSeconds: seconds ?? reps ?? 30)
            case .bodyweightReps:
                return DraftSet(weight: weight, reps: reps ?? 8, completedAt: start)
            case .weightReps:
                return DraftSet(weight: weight, reps: reps ?? 8, completedAt: start)
            }
        }
        return DraftExercise(exerciseRef: exercise.id, sets: sets, notes: note)
    }

    /// The session name after a scan: a WHOOP sport name ("Functional Fitness") gives way to the board's title.
    static func name(current: String, original: String, isWhoopImport: Bool, boardTitle: String) -> String {
        let title = boardTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, current == original, isWhoopImport else { return current }
        return title
    }
}
