import Foundation

/// A session's heart rate as an evenly spaced line, ready to draw. Pure.
enum HeartRateCurve {
    /// WHOOP zones as % of max heart rate: Z1 50–60, Z2 60–70, Z3 70–80, Z4 80–90, Z5 90–100.
    static let zoneFloors: [Double] = [0, 0.5, 0.6, 0.7, 0.8, 0.9]

    static func zone(_ bpm: Double, maxHR: Double) -> Int {
        let share = bpm / maxHR
        return zoneFloors.lastIndex { share >= $0 } ?? 0
    }

    /// Max heart rate for zones: the highest seen in any session, never below 185.
    static func maxHR(history: [WorkoutRow]) -> Double {
        max(185, Double(history.compactMap(\.maxHr).max() ?? 0))
    }

    /// The highest raw sample in [start, end] and when it happened, as a share of the window.
    static func peak(_ samples: [(date: Date, bpm: Double)], start: Date, end: Date) -> (bpm: Double, at: Double)? {
        let span = end.timeIntervalSince(start)
        guard span > 0,
              let top = samples.filter({ $0.date >= start && $0.date <= end }).max(by: { $0.bpm < $1.bpm })
        else { return nil }
        return (top.bpm, top.date.timeIntervalSince(start) / span)
    }

    /// Averages samples into `buckets` equal slices of [start, end], fills gaps by joining neighbours,
    /// then lightly smooths. Returns nil when there's too little data to draw honestly.
    static func resample(_ samples: [(date: Date, bpm: Double)], start: Date, end: Date, buckets: Int = 140) -> [Double]? {
        let span = end.timeIntervalSince(start)
        guard span > 0, buckets > 1 else { return nil }
        var sums = [Double](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for sample in samples where sample.date >= start && sample.date <= end {
            let i = min(buckets - 1, Int(sample.date.timeIntervalSince(start) / span * Double(buckets)))
            sums[i] += sample.bpm
            counts[i] += 1
        }
        let filled = counts.filter { $0 > 0 }.count
        guard filled >= buckets / 4 else { return nil }

        var values: [Double?] = (0..<buckets).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
        // Join gaps linearly; hold the ends flat.
        let known = values.indices.filter { values[$0] != nil }
        for i in values.indices where values[i] == nil {
            let before = known.last { $0 < i }, after = known.first { $0 > i }
            switch (before, after) {
            case let (b?, a?):
                let t = Double(i - b) / Double(a - b)
                values[i] = values[b]! + (values[a]! - values[b]!) * t
            case let (b?, nil): values[i] = values[b]
            case let (nil, a?): values[i] = values[a]
            default: break
            }
        }
        let line = values.map { $0 ?? 0 }
        // 3-point moving average: keeps the shape, drops sensor jitter.
        return line.indices.map { i in
            let window = line[max(0, i - 1)...min(line.count - 1, i + 1)]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}
