import SwiftUI

/// Parses SVG path data (`d` attribute) into a SwiftUI `Path`.
/// Supports M L H V C S Q T A Z in absolute and relative forms, which covers the body-map artwork.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var scanner = Scanner(Array(d.utf8))
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?      // for S/T reflection
        var lastCommand: UInt8 = 0
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard !scanner.atEnd else { break }
            if let c = scanner.peekCommand() {
                command = c
                scanner.advance()
            } else if command == 0 {
                break // numbers before any command: malformed
            }
            let relative = command >= 97 // lowercase
            let base = relative ? current : .zero
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x, y: base.y + y) }

            switch command | 0x20 { // lowercase compare
            case UInt8(ascii: "m"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = pt(x, y); start = current
                path.move(to: current)
                lastControl = nil
                // Subsequent pairs are implicit line-tos.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
                lastCommand = UInt8(ascii: "m")
                continue
            case UInt8(ascii: "l"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = pt(x, y); path.addLine(to: current); lastControl = nil
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current); lastControl = nil
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current); lastControl = nil
            case UInt8(ascii: "c"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c2 = pt(x2, y2)
                current = pt(x, y)
                path.addCurve(to: current, control1: pt(x1, y1), control2: c2)
                lastControl = c2
            case UInt8(ascii: "s"):
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = isCubic(lastCommand) ? reflect(lastControl, about: current) : current
                let c2 = pt(x2, y2)
                current = pt(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case UInt8(ascii: "q"):
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c = pt(x1, y1)
                current = pt(x, y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case UInt8(ascii: "t"):
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let c = isQuad(lastCommand) ? reflect(lastControl, about: current) : current
                current = pt(x, y)
                path.addQuadCurve(to: current, control: c)
                lastControl = c
            case UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rot = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let end = pt(x, y)
                addArc(to: &path, from: current, to: end, rx: rx, ry: ry,
                       rotation: rot, largeArc: large, sweep: sweep)
                current = end; lastControl = nil
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = start; lastControl = nil
                lastCommand = UInt8(ascii: "z")
                command = 0
                continue
            default:
                return path
            }
            lastCommand = command | 0x20
        }
        return path
    }

    private static func isCubic(_ c: UInt8) -> Bool { c == UInt8(ascii: "c") || c == UInt8(ascii: "s") }
    private static func isQuad(_ c: UInt8) -> Bool { c == UInt8(ascii: "q") || c == UInt8(ascii: "t") }

    private static func reflect(_ p: CGPoint?, about c: CGPoint) -> CGPoint {
        guard let p else { return c }
        return CGPoint(x: 2 * c.x - p.x, y: 2 * c.y - p.y)
    }

    /// Endpoint-parameterised elliptical arc → cubic Béziers (SVG spec F.6).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if p0 == p1 { return }
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }

        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)

        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta1
        for i in 0..<segments {
            let t2 = t + step
            let a = point(t), b = point(t2)
            let da = derivative(t), db = derivative(t2)
            let end = i == segments - 1 ? p1 : b
            path.addCurve(to: end,
                          control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                          control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t = t2
        }
    }

    /// Minimal byte scanner for SVG number grammar (handles "1.5.5", "-2-3", "1e-3").
    private struct Scanner {
        let bytes: [UInt8]
        var i = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { i >= bytes.count }
        mutating func advance() { i += 1 }

        mutating func skipSeparators() {
            while i < bytes.count, bytes[i] == 32 || bytes[i] == 44 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13 {
                i += 1
            }
        }

        func peekCommand() -> UInt8? {
            guard i < bytes.count else { return nil }
            let b = bytes[i]
            let isLetter = (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
            return isLetter && b != UInt8(ascii: "e") && b != UInt8(ascii: "E") ? b : nil
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < bytes.count else { return nil }
            let b = bytes[i]
            guard b == UInt8(ascii: "0") || b == UInt8(ascii: "1") else { return nil }
            i += 1
            return b == UInt8(ascii: "1")
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let startIndex = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            var sawDigit = false, sawDot = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= 48 && b <= 57 { sawDigit = true; i += 1 }
                else if b == UInt8(ascii: "."), !sawDot { sawDot = true; i += 1 }
                else { break }
            }
            if sawDigit, i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "-") || bytes[j] == UInt8(ascii: "+") { j += 1 }
                if j < bytes.count, bytes[j] >= 48 && bytes[j] <= 57 {
                    i = j
                    while i < bytes.count, bytes[i] >= 48 && bytes[i] <= 57 { i += 1 }
                }
            }
            guard sawDigit else { i = startIndex; return nil }
            let s = String(decoding: bytes[startIndex..<i], as: UTF8.self)
            return Double(s).map { CGFloat($0) }
        }
    }
}
