import Foundation
import HealthKit

/// Reads the heart-rate samples WHOOP writes to Apple Health. WHOOP's own API has no time series.
enum HealthHeartRate {
    private static let store = HKHealthStore()
    private static let type = HKQuantityType(.heartRate)

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks once; iOS never says whether read access was granted, so callers just try to read.
    static func requestAccess() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [type])
    }

    static func samples(from start: Date, to end: Date) async -> [(date: Date, bpm: Double)] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let results = try? await descriptor.result(for: store) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return results.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    struct Curve {
        let points: [Double]
        let peak: (bpm: Double, at: Double)?
    }

    /// Curves for each section of a card, keyed by section index. Sections without enough samples are left out.
    static func curves(for sections: [ShareCardModel.Section]) async -> [Int: Curve] {
        await requestAccess()
        var out: [Int: Curve] = [:]
        for (index, section) in sections.enumerated() {
            guard let start = section.start, let end = section.end else { continue }
            let samples = await samples(from: start, to: end)
            if let points = HeartRateCurve.resample(samples, start: start, end: end) {
                out[index] = Curve(points: points, peak: HeartRateCurve.peak(samples, start: start, end: end))
            }
        }
        return out
    }
}
