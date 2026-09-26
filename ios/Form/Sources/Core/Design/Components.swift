import SwiftUI

// MARK: - Knurl

/// The diamond crosshatch of a barbell grip, used as a subtle texture.
struct Knurl: View {
    var color: Color = Palette.rule
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                path.move(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Card

struct CardBackground: ViewModifier {
    var fill: Color = Palette.card

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.rule, lineWidth: 1)
            )
    }
}

extension View {
    func card(_ fill: Color = Palette.card) -> some View {
        modifier(CardBackground(fill: fill))
    }
}

// MARK: - Buttons

/// The chunky orange key: START, SET DONE, shutter. Knurled grip ends, a pressed shadow.
struct PrimaryKeyStyle: ButtonStyle {
    var height: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(.headline, design: .monospaced).weight(.bold))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkFixed)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Palette.orangeShadow)
                        .offset(y: pressed ? 1 : 5)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Palette.orange)
                        .overlay(alignment: .leading) {
                            Knurl(color: Palette.orangeShadow.opacity(0.55)).frame(width: 34)
                        }
                        .overlay(alignment: .trailing) {
                            Knurl(color: Palette.orangeShadow.opacity(0.55)).frame(width: 34)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .offset(y: pressed ? 4 : 0)
                }
            }
            .offset(y: pressed ? 0 : -2)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

/// Soft key for steppers: −2.5, +5, etc.
struct StepKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .monospaced).weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: Palette.rule, radius: 0, y: configuration.isPressed ? 0 : 3)
            )
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// Dark pill: END, secondary actions.
struct InkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .monospaced).weight(.bold))
            .tracking(1.5)
            .foregroundStyle(Palette.bone)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(Palette.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Wordmark

/// "form" where the o is a barbell seen end-on: orange plate, collar, chrome sleeve.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: size * 0.02) {
            Text("f")
            BarbellEndMark()
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(y: size * 0.06)
            Text("rm")
        }
        .font(.system(size: size, weight: .heavy).width(.expanded))
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Form")
    }
}

struct BarbellEndMark: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Palette.orange)
                Circle().strokeBorder(Palette.orangeShadow, lineWidth: d * 0.05).padding(d * 0.12)
                Circle().fill(Palette.chalk).padding(d * 0.3)
                Circle().fill(Palette.chrome).padding(d * 0.38)
                Circle().fill(Palette.inkFixed).padding(d * 0.44)
            }
            .frame(width: d, height: d)
        }
    }
}
