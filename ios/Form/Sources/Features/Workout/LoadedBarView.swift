import SwiftUI

/// A barbell seen side-on with the plates for `weight` loaded on each sleeve.
/// Changing the weight animates plates on and off: it doubles as a plate calculator.
struct LoadedBarView: View {
    let weight: Double
    var bar: Double = 20
    var height: CGFloat = 140

    private var plates: [Plate] { PlateMath.plates(total: weight, bar: bar) ?? [] }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let center = geo.size.height / 2
            let unit = min(16, width / 26) // thickness unit for a 25 kg plate
            let collarInset = width * 0.3  // where plates start on each side

            ZStack {
                // Shaft with knurling between the collars
                Capsule().fill(Palette.chrome).frame(width: width - 8, height: 8)
                Knurl(color: Palette.slate.opacity(0.6), spacing: 4)
                    .frame(width: width - collarInset * 2 - 24, height: 8)
                    .clipShape(Capsule())
                // Sleeves (thicker ends)
                HStack {
                    Capsule().fill(Palette.chrome).frame(width: collarInset - 2, height: 14)
                    Spacer()
                    Capsule().fill(Palette.chrome).frame(width: collarInset - 2, height: 14)
                }
                // Collars
                HStack {
                    Spacer().frame(width: collarInset - 8)
                    RoundedRectangle(cornerRadius: 2).fill(Palette.slate).frame(width: 8, height: 26)
                    Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(Palette.slate).frame(width: 8, height: 26)
                    Spacer().frame(width: collarInset - 8)
                }
                // Plates: heaviest nearest the collar, mirrored on the left
                HStack(spacing: 2) {
                    ForEach(Array(plates.enumerated().reversed()), id: \.offset) { _, plate in
                        PlateShape(plate: plate, unit: unit, maxHeight: geo.size.height)
                    }
                }
                .frame(width: collarInset - 10, alignment: .trailing)
                .position(x: (collarInset - 10) / 2, y: center)

                HStack(spacing: 2) {
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        PlateShape(plate: plate, unit: unit, maxHeight: geo.size.height)
                    }
                }
                .frame(width: collarInset - 10, alignment: .leading)
                .position(x: width - (collarInset - 10) / 2, y: center)
            }
            .frame(width: width, height: geo.size.height)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: plates)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if plates.isEmpty { return "Just the bar" }
        return "Bar plus " + plates.map { "\($0.label)" }.joined(separator: ", ") + " kilogram plates on each side"
    }
}

struct PlateShape: View {
    let plate: Plate
    let unit: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        let h = maxHeight * plate.heightRatio
        let w = max(10, unit * 1.6 * plate.thicknessRatio)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(plate.color)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Palette.inkFixed.opacity(0.18), lineWidth: 1)
            )
            .overlay {
                if h > 44 {
                    Text(plate.label)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(plate.labelColor)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: w, height: h)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }
}

extension Plate {
    var color: Color {
        switch self {
        case .p25: Palette.orange
        case .p20: Palette.denimFixed
        case .p15: Palette.slate
        case .p10: Palette.inkFixed
        case .p5: Palette.mist
        case .p2_5: Palette.sand
        case .p1_25: Palette.chrome
        }
    }

    var labelColor: Color {
        switch self {
        case .p20, .p15, .p10: Palette.chalk
        default: Palette.inkFixed
        }
    }
}

/// "BAR 20 + 25 5 1.25 EACH SIDE" readout under the bar.
struct PlateReadout: View {
    let weight: Double
    let bar: Double

    var body: some View {
        HStack(spacing: 6) {
            if let plates = PlateMath.plates(total: weight, bar: bar) {
                if plates.isEmpty {
                    Text("Just the bar").labelStyle(Palette.ink)
                } else {
                    Text("Bar \(bar.kg) +").labelStyle(Palette.ink)
                    ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 1).fill(plate.color).frame(width: 5, height: 12)
                            Text(plate.label).labelStyle(Palette.ink)
                        }
                    }
                    Spacer()
                    Text("each side").labelStyle()
                }
            } else {
                Text("Can't load \(weight.kg) kg exactly").labelStyle(Palette.orangeShadow)
            }
        }
    }
}

/// A pair of hex dumbbells with the weight stamped on the heads.
struct DumbbellPairView: View {
    let weight: Double

    var body: some View {
        HStack(spacing: 28) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 0) {
                    head
                    Capsule().fill(Palette.chrome).frame(width: 44, height: 10)
                    head
                }
            }
        }
        .frame(height: 100)
        .accessibilityLabel("Dumbbells, \(weight.kg) kilograms each")
    }

    private var head: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Palette.inkFixed)
            .frame(width: 30, height: 58)
            .overlay(
                Text(weight.kg)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.chalk)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            )
    }
}
