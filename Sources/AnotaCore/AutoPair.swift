import Foundation

/// VS Code-style bracket/quote pairing. Pure: given the text and selection, returns the edit to make
/// (or nil to let the keystroke through). The editor applies it as one undoable change.
public enum AutoPair {
    public struct Edit: Equatable, Sendable {
        public let range: NSRange      // text to replace
        public let text: String        // replacement
        public let selection: NSRange  // selection afterwards
    }

    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`", "<": ">"]
    static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`", ">"]

    /// Languages that get pairing (not plain text, logs or data files).
    public static func enabled(for l: Language) -> Bool {
        ![.plain, .log, .csv, .tsv, .sqlite, .excel].contains(l)
    }

    /// A typed character. Handles: wrap selection, insert pair, step over an existing closer, outdent a lone closer.
    public static func type(_ c: Character, in text: NSString, selection sel: NSRange, language: Language,
                            indentUnit: String = "    ") -> Edit? {
        guard enabled(for: language) else { return nil }
        let prev = sel.location > 0 ? char(text, sel.location - 1) : nil
        let next = NSMaxRange(sel) < text.length ? char(text, NSMaxRange(sel)) : nil

        // Step over the closer we'd otherwise duplicate: typing ")" before ")".
        if sel.length == 0, closers.contains(c), next == c, !(c == "<") {
            if !isQuote(c) || prev != "\\" {
                return Edit(range: NSRange(location: sel.location, length: 0), text: "",
                            selection: NSRange(location: sel.location + 1, length: 0))
            }
        }
        if let close = pairs[c] {
            if c == "<", !anglePairs(language, prev: prev) { return nil }
            // Wrap a selection: (selected)
            if sel.length > 0, c != "<" || language.isMarkup {
                let inner = text.substring(with: sel)
                return Edit(range: sel, text: String(c) + inner + String(close),
                            selection: NSRange(location: sel.location + 1, length: (inner as NSString).length))
            }
            guard sel.length == 0 else { return nil }
            if isQuote(c) {
                // Not after a word char or backslash (don't, it\'s), not before a word char, and not inside
                // a string already open on this line (odd count of that quote before the caret).
                if let p = prev, p.isLetter || p.isNumber || p == "\\" || p == c { return nil }
                if let n = next, n.isLetter || n.isNumber { return nil }
                if c == "'", [.markdown, .html, .xml].contains(language) { return nil }  // prose apostrophes
            }
            // Only before whitespace, end of line, or a closer/separator (VS Code's "autoCloseBefore").
            if let n = next, !(n.isWhitespace || closers.contains(n) || ",;:.=".contains(n)) { return nil }
            return Edit(range: sel, text: String(c) + String(close), selection: NSRange(location: sel.location + 1, length: 0))
        }
        // A closing bracket typed on a whitespace-only line: drop one indent level first.
        if sel.length == 0, "}])".contains(c) {
            let line = text.lineRange(for: NSRange(location: sel.location, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: sel.location - line.location))
            if !before.isEmpty, before.allSatisfy({ $0 == " " || $0 == "\t" }) {
                let unit = before.hasSuffix("\t") ? "\t" : indentUnit
                let kept = before.hasSuffix(unit) ? String(before.dropLast(unit.count)) : ""
                return Edit(range: NSRange(location: line.location, length: sel.location - line.location),
                            text: kept + String(c), selection: NSRange(location: line.location + (kept as NSString).length + 1, length: 0))
            }
        }
        return nil
    }

    /// Backspace between an empty pair `(|)` deletes both.
    public static func backspace(in text: NSString, selection sel: NSRange, language: Language) -> Edit? {
        guard enabled(for: language), sel.length == 0, sel.location > 0, sel.location < text.length,
              let open = char(text, sel.location - 1), let close = pairs[open], char(text, sel.location) == close
        else { return nil }
        return Edit(range: NSRange(location: sel.location - 1, length: 2), text: "",
                    selection: NSRange(location: sel.location - 1, length: 0))
    }

    /// Return: keep the line's indent; after an opener add one level; between `{|}` put the closer on its own line.
    public static func newline(in text: NSString, selection sel: NSRange, language: Language,
                               indentUnit: String = "    ") -> Edit {
        let line = text.lineRange(for: NSRange(location: sel.location, length: 0))
        let head = text.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        let indent = String(head.prefix { $0 == " " || $0 == "\t" })
        let unit = indent.hasPrefix("\t") ? "\t" : indentUnit
        let prev = head.trimmingCharacters(in: .whitespaces).last
        let next = NSMaxRange(sel) < text.length ? char(text, NSMaxRange(sel)) : nil
        guard enabled(for: language), let p = prev, "({[".contains(p) else {
            return Edit(range: sel, text: "\n" + indent, selection: NSRange(location: sel.location + 1 + (indent as NSString).length, length: 0))
        }
        let inner = "\n" + indent + unit
        if let n = next, pairs[p] == n {
            return Edit(range: sel, text: inner + "\n" + indent,
                        selection: NSRange(location: sel.location + (inner as NSString).length, length: 0))
        }
        return Edit(range: sel, text: inner, selection: NSRange(location: sel.location + (inner as NSString).length, length: 0))
    }

    private static func char(_ s: NSString, _ i: Int) -> Character? {
        guard i >= 0, i < s.length else { return nil }
        return Character(s.substring(with: s.rangeOfComposedCharacterSequence(at: i)))
    }

    private static func isQuote(_ c: Character) -> Bool { c == "\"" || c == "'" || c == "`" }

    /// `<` pairs in markup, and in code only right after a word char (generics: `Array<`), never for `a < b`.
    private static func anglePairs(_ l: Language, prev: Character?) -> Bool {
        if l.isMarkup { return true }
        guard [.swift, .typescript, .tsx, .rust, .cpp, .java, .go].contains(l), let p = prev else { return false }
        return p.isLetter || p.isNumber || p == "_"
    }
}

extension Language {
    public var isMarkup: Bool { self == .html || self == .xml }
}
