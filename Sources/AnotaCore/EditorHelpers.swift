import Foundation

public enum FuzzyMatcher {
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased()), text = Array(candidate.lowercased())
        if needle.isEmpty { return 0 }
        var next = 0, score = 0, previous = -2
        for (i, c) in text.enumerated() where next < needle.count {
            if c == needle[next] {
                score += 10 + (i == previous + 1 ? 12 : 0) + (i == 0 || "/_- .".contains(text[i - 1]) ? 15 : 0)
                previous = i; next += 1
            }
        }
        return next == needle.count ? score - text.count / 4 : nil
    }
}

public enum BracketMatch {
    /// Bounded scan around the caret; balanced mixed bracket types only.
    public static func ranges(in text: NSString, caret: Int, limit: Int = 100_000) -> [NSRange] {
        let opens: [unichar: unichar] = [40: 41, 91: 93, 123: 125]
        let closes = Dictionary(uniqueKeysWithValues: opens.map { ($0.value, $0.key) })
        guard caret >= 0, caret <= text.length else { return [] }
        let at = [caret - 1, caret].first { $0 >= 0 && $0 < text.length && (opens[text.character(at: $0)] != nil || closes[text.character(at: $0)] != nil) }
        guard let at else { return [] }
        let c = text.character(at: at), forward = opens[c] != nil
        var stack: [unichar] = [c], i = at + (forward ? 1 : -1), scanned = 0
        while i >= 0 && i < text.length && scanned < limit {
            let ch = text.character(at: i)
            if forward ? opens[ch] != nil : closes[ch] != nil { stack.append(ch) }
            else if let expected = forward ? closes[ch] : opens[ch] {
                guard stack.last == expected else { return [] }
                stack.removeLast()
                if stack.isEmpty { return [NSRange(location: at, length: 1), NSRange(location: i, length: 1)] }
            }
            i += forward ? 1 : -1; scanned += 1
        }
        return []
    }
}

public enum MarkdownEditing {
    public static func continuation(_ head: String) -> String? {
        let re = try! NSRegularExpression(pattern: #"^(\s*)([-+*]|[0-9]+[.)]) (?:\[([ xX])\] )?(.*)$"#)
        let ns = head as NSString
        guard let m = re.firstMatch(in: head, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indent = ns.substring(with: m.range(at: 1)), marker = ns.substring(with: m.range(at: 2))
        guard !ns.substring(with: m.range(at: 4)).isEmpty else { return "" }
        let next = Int(marker.dropLast()).map { "\($0 + 1)\(marker.suffix(1))" } ?? marker
        return indent + next + " " + (m.range(at: 3).location == NSNotFound ? "" : "[ ] ")
    }
}

public enum Indentation {
    public static func detect(_ text: String) -> String? {
        var widths: [Int: Int] = [:], tabs = 0, spaces = 0
        for line in text.split(separator: "\n").prefix(2000) {
            if line.hasPrefix("\t") { tabs += 1; continue }
            let width = line.prefix { $0 == " " }.count
            if width > 0, width <= 16 { spaces += 1; widths[width, default: 0] += 1 }
        }
        if tabs > spaces { return "\t" }
        guard let width = widths.keys.filter({ (2...8).contains($0) }).min() else { return nil }
        return String(repeating: " ", count: width)
    }
}
