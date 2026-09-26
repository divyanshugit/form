import Foundation

/// A progress photo. The image lives in the private `form-photos` bucket at `storagePath`
/// and is cached on the device by id.
struct ProgressPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var workoutId: UUID?
    var kind: String = "progress"
    var storagePath: String
    var takenAt: Date
    var bodyWeightKg: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case workoutId = "workout_id"
        case storagePath = "storage_path"
        case takenAt = "taken_at"
        case bodyWeightKg = "body_weight_kg"
    }
}

enum PhotoTimeline {
    /// "DAY 1" is the first photo ever; later photos count calendar days from it.
    static func dayNumber(of photo: ProgressPhoto, first: Date?) -> Int {
        guard let first else { return 1 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: photo.takenAt)).day ?? 0
        return max(1, days + 1)
    }

    /// Newest month first, photos newest first within each month.
    static func byMonth(_ photos: [ProgressPhoto]) -> [(month: Date, photos: [ProgressPhoto])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: photos) {
            calendar.dateInterval(of: .month, for: $0.takenAt)?.start ?? $0.takenAt
        }
        return grouped.keys.sorted(by: >).map { month in
            (month, grouped[month]!.sorted { $0.takenAt > $1.takenAt })
        }
    }

    /// Plain-language change between two photos, e.g. "−4.5 kg over 16 weeks".
    static func change(from older: ProgressPhoto, to newer: ProgressPhoto) -> String {
        let days = Calendar.current.dateComponents([.day], from: older.takenAt, to: newer.takenAt).day ?? 0
        let span = days >= 14 ? "\(days / 7) weeks" : "\(days) day\(days == 1 ? "" : "s")"
        guard let a = older.bodyWeightKg, let b = newer.bodyWeightKg else { return span + " apart" }
        let delta = b - a
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "±")
        return "\(sign)\(abs(delta).kg) kg over \(span)"
    }
}
