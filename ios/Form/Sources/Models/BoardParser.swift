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
    /// The text as read, e.g. "→ 12 DDB RDL (T:3.1.1)".
    var raw: String
    /// The exercise words alone, e.g. "DDB RDL".
    var name: String
    var reps: Int?
    /// Top of a rep range ("8-10" → reps 8, repsMax 10).
    var repsMax: Int?
    var sets: Int?
    var seconds: Int?
    var perSide = false
    /// Heading the line sits under, e.g. "Block B" or "Finisher · Tabata".
    var block: String?
    /// Extras worth keeping: tempo, 1½ reps, rest.
    var note: String?

    static func == (a: PlannedLine, b: PlannedLine) -> Bool {
        a.raw == b.raw && a.name == b.name && a.reps == b.reps && a.repsMax == b.repsMax && a.sets == b.sets
            && a.seconds == b.seconds && a.perSide == b.perSide && a.block == b.block && a.note == b.note
    }
}

struct BoardPlan: Equatable {
    var title: String?
    var lines: [PlannedLine]
}

/// Turns recognised text from a whiteboard photo into an ordered list of exercises.
///
/// Pipeline: clean each line (OCR slips, bullets) → classify it (title, heading, "4 Sets" / "40″/10″ × 3"
/// directive, rest, junk or exercise) → join wrapped and ditto lines → pick the title → give each exercise
/// the heading and directive above it in its column.
enum BoardParser {
    static func parse(_ input: [OCRLine]) -> BoardPlan {
        let cleaned = input
            .flatMap(splitMerged)
            .map { OCRLine(text: clean($0.text), box: $0.box) }
            .filter { $0.text.filter(\.isLetter).count >= 2 || scheme(in: $0.text) != nil }
            .sorted { $0.box.midY < $1.box.midY }

        var headings: [Heading] = []
        var directives: [(directive: Directive, box: CGRect)] = []
        var items: [OCRLine] = []
        var titles: [(text: String, box: CGRect, known: Bool)] = []

        for line in cleaned {
            switch classify(line.text) {
            case .junk, .rest:
                continue
            case .title(let text, let known):
                titles.append((text, line.box, known))
                // An unknown short line may just be an exercise ("BENCH PRESS"); keep it unless it becomes the title.
                if !known { items.append(line) }
            case .heading(let label, let directive):
                headings.append(Heading(label: label, box: line.box, directive: directive))
            case .directive(let directive, let rest):
                directives.append((directive, line.box))
                if let rest { items.append(OCRLine(text: rest, box: line.box)) }
            case .item:
                items.append(line)
            }
        }

        let title = pickTitle(titles, items: items, headings: headings)
        if let title { items.removeAll { $0.text.capitalized(firstOnly: true) == title } }
        let blocks = groupHeadings(headings)

        var planned: [(line: PlannedLine, blockIndex: Int, y: CGFloat, x: CGFloat)] = []
        for item in joinWrapped(items) {
            // Nearest heading above, in the same column.
            let blockIndex = blocks.indices
                .filter { blocks[$0].box.midY < item.box.midY && sameColumn(blocks[$0].box, item.box) }
                .max { blocks[$0].box.midY < blocks[$1].box.midY }
            let floor = blockIndex.map { blocks[$0].box.midY } ?? -1
            // Nearest directive between that heading and the line, else the heading's own ("Block A - 4 Sets").
            let directive = directives
                .filter { $0.box.midY < item.box.midY && $0.box.midY > floor && sameColumn($0.box, item.box) }
                .max { $0.box.midY < $1.box.midY }?.directive
                ?? blockIndex.flatMap { blocks[$0].directive }

            var line = parseLine(item.text)
            let nameWords = words(line.name)
            guard line.name.filter(\.isLetter).count >= 2,
                  !(nameWords.count == 1 && movementTails.contains(nameWords[0])) else { continue }
            line.block = blockIndex.map { blocks[$0].label }
            if let directive {
                if line.sets == nil { line.sets = directive.sets }
                if line.reps == nil, line.seconds == nil { line.seconds = directive.seconds }
            }
            planned.append((line, blockIndex ?? Int.max, item.box.midY, item.box.minX))
        }

        let ordered = planned.sorted { a, b in
            if a.blockIndex != b.blockIndex { return a.blockIndex < b.blockIndex }
            if a.blockIndex == Int.max, abs(a.x - b.x) > 0.15 { return a.x < b.x }
            return a.y < b.y
        }
        return BoardPlan(title: title, lines: ordered.map(\.line))
    }

    // MARK: - Cleaning

    /// Cyrillic look-alikes Vision sometimes returns for Latin handwriting ("Воск B").
    private static let lookalikes: [Character: Character] = [
        "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M", "О": "O", "Р": "P", "Т": "T", "Х": "X",
        "а": "a", "с": "c", "е": "e", "к": "k", "о": "o", "р": "p", "х": "x", "у": "y", "ı": "i",
        "ó": "0", "Ó": "0", "ò": "0", "ớ": "0", "ö": "0", "′": "'", "’": "'", "″": "\"", "×": "x",
    ]

    private static let bullets = try! NSRegularExpression(pattern: #"^[\s\-–—•·»>*,.@→=_|+]+"#)
    /// Handwritten digits next to a zero that OCR reads as letters: "ió", "vó", "yó" (4), "gó" (9), "1D".
    private static let slippedDigit = try! NSRegularExpression(pattern: #"(?<![A-Za-z])([iIl|vch]|y|g)0(?![A-Za-z])|(?<![A-Za-z\d])1[DO](?![A-Za-z])"#)
    /// "W/u:" warm-up prefix.
    private static let warmup = try! NSRegularExpression(pattern: #"^w\s*/\s*u\s*:?\s*"#, options: .caseInsensitive)
    /// "10 MIN", "8 min": a block's time cap.
    private static let timeCap = try! NSRegularExpression(pattern: #"^\d+\s*min\.?$"#, options: .caseInsensitive)
    /// "A1." / "B2)" exercise labels and "2)" list markers.
    private static let label = try! NSRegularExpression(pattern: #"^(?:[A-Da-d]\d|\d)\s*[.)]\s*"#)

    /// Fixes OCR slips and strips bullets and labels; keeps everything else.
    static func clean(_ text: String) -> String {
        var s = String(text.map { lookalikes[$0] ?? $0 })
        s = s.replacingOccurrences(of: #"(?<=0)h0"#, with: "/10", options: .regularExpression)
        s = replace(slippedDigit, in: s) { match, ns in
            let token = ns.substring(with: match.range)
            if token.hasPrefix("1") { return "10" }
            switch token.first {
            case "y": return "40"
            case "g": return "90"
            default: return "10"
            }
        }
        s = bullets.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        s = label.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        s = warmup.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Classifying

    private enum Kind {
        case junk, rest
        case title(String, known: Bool)
        case heading(String, Directive?)
        /// A directive, and any exercise text that followed it on the same line.
        case directive(Directive, rest: String?)
        case item
    }

    /// "4 Sets" → sets 4; "40″/10″ × 3" → 40 s work, 3 rounds.
    struct Directive: Equatable {
        var sets: Int?
        var seconds: Int?
    }

    private struct Heading {
        var label: String
        var box: CGRect
        var directive: Directive?
    }

    /// Class names written at the top of Omni boards. Matched loosely, so "Fallbody_" reads as "Fullbody".
    static let classNames = [
        "Fullbody", "DB Fullbody", "Coreflow", "Core & Abs", "Abs & Core", "Kettlebells", "Kettlebell Strength",
        "Kettlebell Fullbody", "Strength 101", "Upper Body", "Lower Body", "Mobility", "Hyrox",
    ]

    private static let brandWords: Set<String> = ["omni", "omi", "concept", "vtec", "rooftop", "classes", "class", "start", "sprint"]

    private static let headingFirstWords: Set<String> = [
        "block", "finisher", "tabata", "warmup", "warm", "cooldown", "circuit", "emom", "amrap", "superset",
        "power", "strength", "engine", "activation", "lower", "upper", "accessory", "accessories", "complex",
    ]
    private static let coreHeadingWords: Set<String> = ["core", "abs", "low", "flow"]
    private static let roundWords: Set<String> = ["sets", "set", "sels", "sots", "rounds", "round", "rnds", "rds"]

    private static func classify(_ text: String) -> Kind {
        let w = words(text)
        guard !w.isEmpty || scheme(in: text) != nil else { return .junk }

        // Rest markers: "- Rest -", "Rest 30'".
        if w.first == "rest" || (w.count <= 2 && w.contains { editDistance($0, "rest") <= 1 || $0 == "lose" }) { return .rest }
        if text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { return .junk }
        if w.count <= 2, w.contains(where: { editDistance($0, "rowerg") <= 1 || editDistance($0, "skierg") <= 1 }) { return .junk }

        if timeCap.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return .junk }

        // Brand, signage and start times.
        if text.contains("@") || (!w.isEmpty && w.allSatisfy { brandWords.contains($0) || $0.count <= 1 }) { return .junk }

        if let known = knownClass(text) { return .title(known, known: true) }

        if isHeading(text) {
            let (label, directive) = splitHeading(text)
            return .heading(label, directive)
        }

        let leadsWithNumber = text.first?.isNumber == true
        let hasRoundWord = w.contains { roundWords.contains($0) || isRoundsTypo($0) }
        if let found = scheme(in: text) {
            var directive = found.directive
            if directive.sets == nil, hasRoundWord { directive.sets = leadingNumber(text) }
            let rest = exerciseText(after: found.range, in: text)
            return .directive(directive, rest: rest)
        }
        if hasRoundWord {
            let numbers = allNumbers(text)
            let n = numbers.first
            // "3 RaNOS 40 20": rounds, then work and rest seconds.
            if numbers.count >= 3, (10...300).contains(numbers[1]) {
                return .directive(Directive(sets: n, seconds: numbers[1]), rest: nil)
            }
            // "4 Sets: 12 Alt. KBS": the directive, then an exercise.
            if let colon = text.firstIndex(of: ":") {
                let after = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if words(after).filter({ !["lops", "laps"].contains($0) }).count >= 1, after.filter(\.isLetter).count >= 3 {
                    return .directive(Directive(sets: n), rest: after)
                }
            }
            let rest = w.filter { !roundWords.contains($0) && !isRoundsTypo($0) && !["x", "lops", "laps"].contains($0) }
            // "3 Sets" alone, or "Sets: 2 Laps": a directive. Anything longer is an exercise that says "sets".
            if rest.isEmpty || (rest.count <= 1 && !leadsWithNumber) { return .directive(Directive(sets: n), rest: nil) }
        }

        // A short line without a number at the very top could be the class name ("Kettlebell Fullbody").
        if !leadsWithNumber, w.count <= 3 { return .title(text, known: false) }
        return .item
    }

    /// Known heading words lead the line ("Block C 10 Min", "Finisher 20x3", "UPPER STRENGTH");
    /// "Core & Abs" style column labels count too.
    static func isHeading(_ text: String) -> Bool {
        guard let first = text.first, !first.isNumber else { return false }
        let w = words(text)
        guard let lead = w.first, w.count <= 4 else { return false }
        if headingFirstWords.contains(lead) || isBlockTypo(lead) || fuzzyHeading(lead) { return true }
        return w.allSatisfy { coreHeadingWords.contains($0) } && w.contains("core")
    }

    /// "Bock", "BloCKA", "BOCKA", "Blk".
    private static func isBlockTypo(_ word: String) -> Bool {
        if ["bock", "blk", "blok", "bloc"].contains(word) { return true }
        if word.count == 6, let last = word.last, "abcd".contains(last) {
            return editDistance(String(word.dropLast()), "block") <= 1
        }
        if word.count == 5, let last = word.last, "abcd".contains(last), word.hasPrefix("b") {
            return editDistance(String(word.dropLast()), "bock") <= 1 || editDistance(word, "block") <= 1
        }
        return false
    }

    /// "STRENGT", "STRENGIH", "Frisher", "Finisherü".
    private static func fuzzyHeading(_ word: String) -> Bool {
        guard word.count >= 6 else { return false }
        return ["strength", "finisher", "activation", "accessory"].contains { editDistance(word, $0) <= 2 }
    }

    private static func isRoundsTypo(_ word: String) -> Bool {
        if ["rands", "ranos", "ronos", "ronds", "raunds", "pounds", "rnds"].contains(word) { return true }
        return (5...6).contains(word.count) && (word.hasPrefix("r") || word.hasPrefix("p")) && editDistance(word, "rounds") <= 2
    }

    /// Headings stacked in the same column ("Finisher" over "Tabata") become one label, in reading order.
    private static func groupHeadings(_ headings: [Heading]) -> [Heading] {
        var blocks: [Heading] = []
        for heading in headings.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let i = blocks.lastIndex(where: {
                abs($0.box.minX - heading.box.minX) < 0.15 && heading.box.midY - $0.box.maxY < 0.05
            }) {
                blocks[i].label += " · " + heading.label
                blocks[i].box = blocks[i].box.union(heading.box)
                blocks[i].directive = blocks[i].directive ?? heading.directive
            } else {
                blocks.append(heading)
            }
        }
        // Rows top to bottom, then left to right.
        return blocks.sorted { a, b in
            abs(a.box.midY - b.box.midY) < 0.04 ? a.box.minX < b.box.minX : a.box.midY < b.box.midY
        }
    }

    /// "Block A - 4 Sets" → ("Block A", sets 4); "Finisher 20x3" → ("Finisher", 20 s × 3); "Bock At" → "Block A".
    private static func splitHeading(_ text: String) -> (String, Directive?) {
        var directive: Directive?
        var label = text
        if let found = scheme(in: text) {
            directive = found.directive
            label = (text as NSString).substring(to: found.range.location)
        } else if let m = setsSuffix.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let ns = text as NSString
            directive = Directive(sets: Int(ns.substring(with: m.range(at: 1))))
            label = ns.substring(to: m.range.location)
        }
        return (cleanHeading(label.trimmingCharacters(in: CharacterSet(charactersIn: " -–—•.:"))), directive)
    }

    private static let setsSuffix = try! NSRegularExpression(
        pattern: #"[\s\-–—•.:]*(\d+)\s*(?:x|sets?|rounds?)\s*$"#, options: .caseInsensitive)

    /// "Bock At" → "Block A"; "BloCKA" → "Block A"; "Block (" → "Block C".
    private static func cleanHeading(_ text: String) -> String {
        var parts = text.split(separator: " ").map(String.init)
        guard let first = parts.first else { return text }
        let lower = first.lowercased().filter(\.isLetter)
        if isBlockTypo(lower) || lower == "block" {
            var letter: String?
            if lower.count >= 5, let last = lower.last, "abcd".contains(last), lower != "block" {
                letter = String(last).uppercased()
            } else if parts.count > 1 {
                let next = parts[1]
                if next == "(" { letter = "C" } else if let c = next.first, c.isLetter { letter = String(c).uppercased() }
                parts.remove(at: 1)
            }
            parts[0] = "Block" + (letter.map { " " + $0 } ?? "")
        } else if fuzzyHeading(lower) {
            parts[0] = ["strength", "finisher", "activation", "accessory"]
                .min { editDistance(lower, $0) < editDistance(lower, $1) }!.capitalized
        }
        return parts.joined(separator: " ").capitalized(firstOnly: true)
    }

    /// Canonical class name for a loosely read title ("DB FUllBOOY" → "DB Fullbody").
    static func knownClass(_ text: String) -> String? {
        let key = text.lowercased().filter { $0.isLetter || $0.isNumber }
        guard key.count >= 5 else { return nil }
        return classNames
            .map { ($0, editDistance(key, $0.lowercased().filter { $0.isLetter || $0.isNumber })) }
            .filter { $0.1 <= max(1, (key.count + 2) / 4) }
            .min { $0.1 < $1.1 }?.0
    }

    /// A known class name wins; otherwise the topmost short line above every heading and exercise.
    private static func pickTitle(_ titles: [(text: String, box: CGRect, known: Bool)],
                                  items: [OCRLine], headings: [Heading]) -> String? {
        if let known = titles.filter(\.known).min(by: { $0.box.midY < $1.box.midY }) { return known.text }
        let unknown = Set(titles.filter { !$0.known }.map(\.text))
        let firstContent = (items.filter { !unknown.contains($0.text) }.map(\.box.midY) + headings.map(\.box.midY)).min() ?? 1
        return titles
            .filter { $0.box.midY < firstContent - 0.01 && words($0.text).count >= 2 }
            .min { $0.box.midY < $1.box.midY }
            .map { $0.text.capitalized(firstOnly: true) }
    }

    // MARK: - Schemes

    /// "40'/10' x3", "30 / 10 x 3", "20' Hold - 10' Move x 3", "3 x 20' Hold – 10' Move", "(40/20x3)".
    private static let workRest = try! NSRegularExpression(
        pattern: #"\(?\s*(\d{1,3})\s*['"]?\s*(?:hold)?\s*(?:/|off|-|–|on|work)\s*(\d{1,3})\s*['"]?\s*(?:move|off|rest|hold|had)?\s*(?:x\s*(\d{1,2}))?\s*\)?"#,
        options: .caseInsensitive)
    private static let holdMove = try! NSRegularExpression(
        pattern: #"(\d{1,3})\s*['"]?\s*hold\W*(\d{1,3})\s*['"]?\s*move(?:\s*x\s*(\d{1,2}))?"#, options: .caseInsensitive)
    private static let roundsFirst = try! NSRegularExpression(
        pattern: #"(\d{1,2})\s*x\s*(\d{2,3})\s*['"]?\s*(?:hold|work|on)?"#, options: .caseInsensitive)
    private static let workTimesRounds = try! NSRegularExpression(
        pattern: #"(?<![\d/])(\d{2,3})\s*['"]?\s*(?:on|hold)?\s*x\s*(\d{1,2})(?!\d)"#, options: .caseInsensitive)

    static func scheme(in text: String) -> (directive: Directive, range: NSRange)? {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? {
            m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i)))
        }
        if let m = holdMove.firstMatch(in: text, range: all), let work = int(m, 1), (10...300).contains(work) {
            return (Directive(sets: int(m, 3), seconds: work), m.range)
        }
        if let m = roundsFirst.firstMatch(in: text, range: all), let rounds = int(m, 1), let work = int(m, 2),
           rounds <= 10, (10...300).contains(work) {
            // "3 x 20' Hold - 10' Move" also matches work/rest; extend over it.
            let tail = workRest.firstMatch(in: text, range: NSRange(location: m.range.location + 1, length: ns.length - m.range.location - 1))
            let end = max(m.range.upperBound, tail?.range.upperBound ?? 0)
            return (Directive(sets: rounds, seconds: work), NSRange(location: m.range.location, length: end - m.range.location))
        }
        if let m = workRest.firstMatch(in: text, range: all), let work = int(m, 1), let rest = int(m, 2),
           (10...300).contains(work), (0...120).contains(rest), rest < work || int(m, 3) != nil,
           !ns.substring(from: m.range.upperBound).lowercased().hasPrefix("side") {
            // "8-10 Push Ups" is a rep range, not work/rest: needs a quote mark, "x rounds", or a slash.
            let matched = ns.substring(with: m.range)
            guard matched.contains("/") || matched.contains("'") || matched.contains("\"") || int(m, 3) != nil
                    || ["hold", "off", "work"].contains(where: matched.lowercased().contains) else { return nil }
            return (Directive(sets: int(m, 3), seconds: work), m.range)
        }
        if let m = workTimesRounds.firstMatch(in: text, range: all), let work = int(m, 1), let rounds = int(m, 2),
           (10...300).contains(work), rounds <= 10 {
            return (Directive(sets: rounds, seconds: work), m.range)
        }
        return nil
    }

    /// Exercise words left on a directive line ("40/10x3, Crossbody Planted Crunch" → "Crossbody Planted Crunch").
    private static func exerciseText(after range: NSRange, in text: String) -> String? {
        let ns = text as NSString
        let before = ns.substring(to: range.location)
        let after = ns.substring(from: range.upperBound)
        let rest = clean((before + " " + after).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.()")))
        let w = words(rest).filter {
            !roundWords.contains($0) && !isRoundsTypo($0) && !["x", "hold", "move", "work", "activation", "off", "send", "it"].contains($0)
        }
        return w.count >= 2 ? rest : nil
    }

    // MARK: - Joining lines

    private static let movementTails: Set<String> = ["hold", "pulse", "move", "twists", "twist", "rotate", "kick"]
    private static let joiners: Set<String> = ["the", "to", "of", "a", "w"]

    /// Short lines under an exercise in the same column are either its wrapped tail ("Raise" under
    /// "8 DB Front lateral") or a ditto ("____ Pulse R/L" under "Crunch Hold R/L" → "Crunch Pulse").
    /// Expects lines sorted top to bottom. Each line takes at most one tail.
    private static func joinWrapped(_ lines: [OCRLine]) -> [OCRLine] {
        var result: [OCRLine] = []
        var hasTail = Set<Int>()
        for item in lines {
            let itemWords = words(stripSides(item.text))
            // One word ("Raise"), or a lowercase continuation ("the World").
            let meaningful = itemWords.filter { $0.count >= 2 && !joiners.contains($0) }
            let isShort = item.text.first.map { !$0.isNumber } == true && (1...2).contains(itemWords.count)
                && (meaningful.count <= 1 || item.text.first?.isLowercase == true)
            let parent = isShort ? result.lastIndex { last in
                item.box.minX >= last.box.minX - 0.01 && item.box.minX - last.box.minX < 0.2
                    && item.box.minY > last.box.midY
                    && item.box.minY - last.box.maxY < max(0.03, last.box.height * 1.2)
            } : nil
            let ditto = parent.map { isDitto(item.text, under: result[$0].text) } ?? false
            // A wrapped tail is indented under its line, and a line ending in R/L is already complete.
            let wraps = parent.map { p in
                !hasTail.contains(p) && item.box.minX > result[p].box.minX + 0.012
                    && result[p].text == stripSides(result[p].text)
                    && !(words(result[p].text).last.map(movementTails.contains) ?? false)
            } ?? false
            // "____ Hold R/L" under "Side Bend Crunch R/L": the same exercise as a hold.
            let variant = parent.map { p in
                !ditto && result[p].text != stripSides(result[p].text)
                    && itemWords.first.map(movementTails.contains) == true
            } ?? false
            if let parent, variant {
                result.append(OCRLine(text: stripSides(result[parent].text) + " " + item.text, box: item.box))
                continue
            }
            guard let parent, ditto || wraps else {
                result.append(item)
                continue
            }
            let last = result[parent]
            if ditto {
                // Same exercise, different movement: swap the last movement word.
                var base = words(stripSides(last.text)).isEmpty ? last.text : stripSides(last.text)
                if let range = base.range(of: #"\s+\S+\s*$"#, options: .regularExpression) { base.removeSubrange(range) }
                let sides = last.text != stripSides(last.text) || item.text != stripSides(item.text)
                result.append(OCRLine(text: base + " " + stripSides(item.text) + (sides ? " R/L" : ""), box: item.box))
            } else {
                result[parent] = OCRLine(text: last.text + " " + item.text, box: last.box.union(item.box))
                hasTail.insert(parent)
            }
        }
        return result
    }

    private static func isDitto(_ text: String, under parent: String) -> Bool {
        let w = words(stripSides(text)), p = words(stripSides(parent))
        guard let first = w.first, movementTails.contains(first), let last = p.last, p.count >= 2 else { return false }
        return movementTails.contains(last)
    }

    // MARK: - Lines

    private static let prefix = try! NSRegularExpression(
        pattern: #"^\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*(?:[x]\s*(\d+))?\s*(?:(s|sec|secs|seconds|'|")(?![a-z]))?\s*(/\s*(?:side|s|leg|arm|each)\b\.?|each(?:\s+side)?\b|e/s\b)?\s*[-–:.]?\s*"#,
        options: .caseInsensitive)
    private static let suffix = try! NSRegularExpression(
        pattern: #"\s*[-–:]?\s*(\d+)\s*[x]\s*(\d+)\s*$"#, options: .caseInsensitive)
    private static let suffixPerSide = try! NSRegularExpression(
        pattern: #"\s+(\d+)\s*/\s*side\s*$"#, options: .caseInsensitive)
    private static let sides = try! NSRegularExpression(
        pattern: #"\s*\(?(?:\b|(?<=[a-z]))(?:R\s*[/I|l]\s*L|R\s*/\s*K|RK|RIL)\b\)?"#, options: [])
    private static let tempo = try! NSRegularExpression(
        pattern: #"\(\s*(?:T|H)?\s*[:.]?\s*(\d(?:[.\s]?\d){2,3})\s*\)?|\(?\s*\bT\s*[:.]?\s*(\d(?:[.\s]?\d){2,3})\s*\)?"#, options: [])
    private static let oneAndHalf = try! NSRegularExpression(pattern: #"\(\s*1[.,]5\s*\)?"#)
    private static let trailingRest = try! NSRegularExpression(
        pattern: #"\s*[-–—.•]*\s*\brest\b.*$"#, options: .caseInsensitive)

    /// "→ 8-10 /side FFE Split lunges" → reps 8–10, per side, name "FFE Split lunges".
    private static let repScheme = try! NSRegularExpression(pattern: #"^\s*(\d{1,3}(?:\s*[-–]\s*\d{1,3}){2,})\s+(?=[A-Za-z])"#)
    private static let distancePrefix = try! NSRegularExpression(
        pattern: #"^\s*(\d{2,4}|\d(?:[.,]\d)?)\s*(m|km)\b\s*"#, options: [.caseInsensitive])
    private static let distanceSuffix = try! NSRegularExpression(
        pattern: #"\s(\d{2,4}|\d(?:[.,]\d)?)\s*(m|km)\s*$"#, options: [.caseInsensitive])

    static func parseLine(_ text: String) -> PlannedLine {
        var line = PlannedLine(raw: text, name: text)
        var s = clean(text)
        var notes: [String] = []

        s = replace(trailingRest, in: s) { _, _ in "" }
        if s != stripSides(s) {
            line.perSide = true
            s = stripSides(s)
        }
        if let m = tempo.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let ns = s as NSString
            let group = m.range(at: 1).location != NSNotFound ? 1 : 2
            let digits = ns.substring(with: m.range(at: group)).filter(\.isNumber)
            notes.append("tempo " + digits.map(String.init).joined(separator: "-"))
            s = ns.replacingCharacters(in: m.range, with: "")
        }
        if oneAndHalf.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
            notes.append("1½ reps")
            s = replace(oneAndHalf, in: s) { _, _ in "" }
        }

        // "15-9-6 Thrusters" (a descending scheme) or "1-2-3-4-5 Pull-ups" (a ladder): one set per number.
        if let m = repScheme.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let ns = s as NSString
            let numbers = ns.substring(with: m.range(at: 1)).split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count >= 3, numbers.allSatisfy({ $0 > 0 && $0 <= 100 }) {
                let ascending = zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 }
                line.sets = numbers.count
                line.reps = ascending ? numbers.last : numbers.first
                notes.append((ascending ? "ladder " : "") + numbers.map(String.init).joined(separator: "-") + " reps")
                s = ns.replacingCharacters(in: m.range, with: "")
            }
        }
        // "500m Row", "1 km Run", "Row 500 m": the distance goes in the note.
        for pattern in [distancePrefix, distanceSuffix] {
            if let m = pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                let ns = s as NSString
                let amount = ns.substring(with: m.range(at: 1))
                let unit = ns.substring(with: m.range(at: 2)).lowercased()
                notes.append("\(amount) \(unit)")
                s = ns.replacingCharacters(in: m.range, with: " ")
                break
            }
        }

        let ns = s as NSString
        let all = NSRange(location: 0, length: ns.length)
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? {
            m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i)))
        }
        if let m = prefix.firstMatch(in: s, range: all), m.range.length > 0, int(m, 1) != nil {
            let first = int(m, 1)
            if let times = int(m, 3) {
                line.sets = first
                line.reps = times
            } else if m.range(at: 4).location != NSNotFound {
                line.seconds = first
            } else {
                line.reps = first
                line.repsMax = int(m, 2)
            }
            if m.range(at: 5).location != NSNotFound { line.perSide = true }
            s = ns.substring(from: m.range.upperBound)
        } else if let m = suffixPerSide.firstMatch(in: s, range: all) {
            line.reps = int(m, 1)
            line.perSide = true
            s = ns.substring(to: m.range.location)
        } else if let m = suffix.firstMatch(in: s, range: all) {
            line.sets = int(m, 1)
            line.reps = int(m, 2)
            s = ns.substring(to: m.range.location)
        }

        if let max = line.repsMax, let min = line.reps {
            if max <= min { line.repsMax = nil } else { notes.insert("\(min)–\(max) reps", at: 0) }
        }
        line.name = s
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(CharacterSet(charactersIn: "→•»*")))
        line.note = notes.isEmpty ? nil : notes.joined(separator: " · ")
        return line
    }

    private static func stripSides(_ text: String) -> String {
        replace(sides, in: text) { _, _ in "" }.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    private static func sameColumn(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.15 || (a.minX < b.maxX && b.minX < a.maxX && abs(a.midX - b.minX) < 0.2)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }

    private static func firstNumber(_ text: String) -> Int? {
        text.range(of: #"\d+"#, options: .regularExpression).flatMap { Int(text[$0]) }
    }

    private static func allNumbers(_ text: String) -> [Int] {
        (try! NSRegularExpression(pattern: #"\d+"#))
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Int((text as NSString).substring(with: $0.range)) }
    }

    /// OCR sometimes reads two board lines as one, joined by a bullet: "DB OH Scissors • Heel Touches".
    private static func splitMerged(_ line: OCRLine) -> [OCRLine] {
        let parts = line.text.components(separatedBy: " • ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count > 1, parts.allSatisfy({ $0.filter(\.isLetter).count >= 3 }) else { return [line] }
        return parts.enumerated().map { i, text in
            OCRLine(text: text, box: line.box.offsetBy(dx: 0, dy: CGFloat(i) * 0.0005))
        }
    }

    private static func leadingNumber(_ text: String) -> Int? {
        text.range(of: #"^\d+"#, options: .regularExpression).flatMap { Int(text[$0]) }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String,
                                with transform: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = text as NSString
        var result = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            result = (result as NSString).replacingCharacters(in: m.range, with: transform(m, ns))
        }
        return result
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

private extension String {
    /// Uppercases the first letter of each word without lowercasing the rest ("RDL" stays "RDL").
    func capitalized(firstOnly: Bool) -> String {
        split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
