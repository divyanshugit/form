import CoreGraphics
import Foundation

/// A line of text found in a photo. `box` is normalised (0…1) with the origin at the TOP left.
struct OCRLine: Equatable {
    var text: String
    var box: CGRect
}

/// One exercise line from a workout board, before it's matched to the library.
struct PlannedLine: Identifiable, Equatable {
    let id = UUID()
    /// The text as read, e.g. "12 KB Bent Over Row".
    var raw: String
    /// The exercise words without the rep prefix, e.g. "KB Bent Over Row".
    var name: String
    var reps: Int?
    var sets: Int?
    var seconds: Int?
    var perSide = false
    /// Heading the line sits under, e.g. "Block B" or "Finisher · Tabata".
    var block: String?

    static func == (a: PlannedLine, b: PlannedLine) -> Bool {
        a.raw == b.raw && a.name == b.name && a.reps == b.reps && a.sets == b.sets
            && a.seconds == b.seconds && a.perSide == b.perSide && a.block == b.block
    }
}

struct BoardPlan: Equatable {
    var title: String?
    var lines: [PlannedLine]
}

/// Turns recognised text from a whiteboard photo into an ordered list of exercises.
/// Headings ("Block A", "Finisher") group the lines under them by column; a one-word line at the
/// very top ("Fullbody") becomes the workout title; wrapped lines are joined back together.
enum BoardParser {
    private static let headingWords: Set<String> = [
        "block", "bock", "blk", "finisher", "tabata", "warmup", "warm", "cooldown", "circuit",
        "emom", "amrap", "superset", "round", "rounds", "complex", "core", "accessory", "accessories",
    ]

    static func parse(_ input: [OCRLine]) -> BoardPlan {
        let lines = input
            .map { OCRLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { $0.text.filter(\.isLetter).count >= 2 }
            .sorted { $0.box.midY < $1.box.midY }

        var headings: [OCRLine] = []
        var items: [OCRLine] = []
        for line in joinWrapped(lines) {
            if isHeading(line.text) { headings.append(line) } else { items.append(line) }
        }

        // Title: the topmost heading, if it's clearly above everything and isn't a block keyword.
        var title: String?
        if let top = headings.first, !isBlockKeyword(top.text),
           lines.allSatisfy({ $0 == top || $0.box.midY > top.box.midY + 0.02 }) {
            title = top.text.capitalized
            headings.removeFirst()
        }

        let blocks = groupHeadings(headings)

        var planned: [(line: PlannedLine, blockIndex: Int, y: CGFloat, x: CGFloat)] = []
        for item in items {
            // Nearest heading above, in the same column.
            let blockIndex = blocks.indices
                .filter { blocks[$0].box.midY < item.box.midY && abs(blocks[$0].box.minX - item.box.minX) < 0.15 }
                .max { blocks[$0].box.midY < blocks[$1].box.midY }
            var line = parseLine(item.text)
            line.block = blockIndex.map { blocks[$0].label }
            planned.append((line, blockIndex ?? Int.max, item.box.midY, item.box.minX))
        }

        let ordered = planned.sorted { a, b in
            if a.blockIndex != b.blockIndex { return a.blockIndex < b.blockIndex }
            if a.blockIndex == Int.max, abs(a.x - b.x) > 0.15 { return a.x < b.x }
            return a.y < b.y
        }
        return BoardPlan(title: title, lines: ordered.map(\.line))
    }

    // MARK: Headings

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    private static func isBlockKeyword(_ text: String) -> Bool {
        words(text).contains { headingWords.contains($0) }
    }

    /// No leading number, and either a known heading word or a single short word.
    static func isHeading(_ text: String) -> Bool {
        guard let first = text.first, !first.isNumber else { return false }
        let w = words(text)
        if w.first.map({ headingWords.contains($0) }) == true, w.count <= 3 { return true }
        return w.count == 1 && text.count <= 14
    }

    private struct Block { var label: String; var box: CGRect }

    /// Headings stacked in the same column ("Finisher" over "Tabata") become one label.
    private static func groupHeadings(_ headings: [OCRLine]) -> [Block] {
        var blocks: [Block] = []
        for heading in headings.sorted(by: { $0.box.midY < $1.box.midY }) {
            let label = cleanHeading(heading.text)
            if let i = blocks.lastIndex(where: {
                abs($0.box.minX - heading.box.minX) < 0.15 && heading.box.midY - $0.box.maxY < 0.08
            }) {
                blocks[i].label += " · " + label
                blocks[i].box = blocks[i].box.union(heading.box)
            } else {
                blocks.append(Block(label: label, box: heading.box))
            }
        }
        // Reading order: rows top to bottom, then left to right.
        return blocks.sorted { a, b in
            abs(a.box.midY - b.box.midY) < 0.04 ? a.box.minX < b.box.minX : a.box.midY < b.box.midY
        }
    }

    /// "Bock At" → "Block A".
    private static func cleanHeading(_ text: String) -> String {
        var w = text.split(separator: " ").map(String.init)
        if let first = w.first?.lowercased(), ["bock", "blk", "block"].contains(first) {
            w[0] = "Block"
            if w.count > 1, let letter = w[1].first, letter.isLetter { w[1] = String(letter).uppercased() }
        }
        return w.joined(separator: " ").capitalized(firstOnly: true)
    }

    // MARK: Lines

    /// A short, indented line right under a numbered line in the same column is its wrapped tail ("Raise").
    /// Expects lines sorted top to bottom.
    private static func joinWrapped(_ lines: [OCRLine]) -> [OCRLine] {
        var result: [OCRLine] = []
        for item in lines {
            let isTail = item.text.first.map { !$0.isNumber } == true
                && words(item.text).count <= 2
                && !isBlockKeyword(item.text)
            let parent = isTail ? result.lastIndex { last in
                last.text.first?.isNumber == true
                    && item.box.minX >= last.box.minX - 0.005 && item.box.minX - last.box.minX < 0.12
                    && item.box.minY > last.box.midY
                    && item.box.minY - last.box.maxY < max(0.03, last.box.height * 1.2)
            } : nil
            if let parent {
                let last = result[parent]
                result[parent] = OCRLine(text: last.text + " " + item.text, box: last.box.union(item.box))
            } else {
                result.append(item)
            }
        }
        return result
    }

    private static let prefix = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*(?:[x×]\s*(\d+))?\s*(?:(s|sec|secs|seconds)\b)?\s*(/\s*(?:side|s|leg|arm|each)\b\.?|each(?:\s+side)?\b|e/s\b)?\s*[-–:.]?\s*"#,
        options: .caseInsensitive)
    private static let suffix = try! NSRegularExpression(
        pattern: #"\s*[-–:]?\s*(\d+)\s*[x×]\s*(\d+)\s*$"#, options: .caseInsensitive)

    /// "8/Side Uneven Stance RDL" → reps 8, per side, name "Uneven Stance RDL".
    static func parseLine(_ text: String) -> PlannedLine {
        var line = PlannedLine(raw: text, name: text)
        let ns = text as NSString
        if let m = prefix.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            let first = Int(ns.substring(with: m.range(at: 1)))
            let second = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) : nil
            let isTime = m.range(at: 3).location != NSNotFound
            if let second {
                line.sets = first
                line.reps = second
            } else if isTime {
                line.seconds = first
            } else {
                line.reps = first
            }
            line.perSide = m.range(at: 4).location != NSNotFound
            line.name = ns.substring(from: m.range.location + m.range.length)
        } else if let m = suffix.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            line.sets = Int(ns.substring(with: m.range(at: 1)))
            line.reps = Int(ns.substring(with: m.range(at: 2)))
            line.name = ns.substring(to: m.range.location)
        }
        line.name = line.name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return line
    }
}

private extension String {
    /// Uppercases the first letter of each word without lowercasing the rest ("RDL" stays "RDL").
    func capitalized(firstOnly: Bool) -> String {
        split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
