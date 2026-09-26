import Foundation

/// Calibrated plates, heaviest first. Drives both the loaded-bar drawing and the plate calculator.
enum Plate: Double, CaseIterable, Identifiable, Sendable {
    case p25 = 25, p20 = 20, p15 = 15, p10 = 10, p5 = 5, p2_5 = 2.5, p1_25 = 1.25

    var id: Double { rawValue }

    var label: String {
        rawValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rawValue))
            : String(rawValue)
    }

    /// Relative plate diameter (0...1) for the side-on drawing.
    var heightRatio: Double {
        switch self {
        case .p25, .p20: 1.0
        case .p15: 0.86
        case .p10: 0.72
        case .p5: 0.52
        case .p2_5: 0.42
        case .p1_25: 0.34
        }
    }

    /// Relative plate thickness for the side-on drawing.
    var thicknessRatio: Double {
        switch self {
        case .p25: 1.0
        case .p20: 0.9
        case .p15: 0.78
        case .p10: 0.66
        case .p5: 0.5
        case .p2_5: 0.42
        case .p1_25: 0.36
        }
    }
}

enum PlateMath {
    /// Greedy per-side breakdown for a bar-loaded lift.
    /// Returns nil when the weight is below the bar or can't be made exactly with calibrated plates.
    static func plates(total: Double, bar: Double) -> [Plate]? {
        guard total >= bar else { return nil }
        var remaining = ((total - bar) / 2 * 100).rounded() / 100
        var result: [Plate] = []
        for plate in Plate.allCases {
            while remaining + 0.0001 >= plate.rawValue {
                result.append(plate)
                remaining -= plate.rawValue
            }
        }
        return remaining < 0.01 ? result : nil
    }

    /// Epley estimated one-rep max.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }
}

extension Double {
    /// "82.5", "80" — kilograms without trailing zeros.
    var kg: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(format: "%g", self)
    }
}
