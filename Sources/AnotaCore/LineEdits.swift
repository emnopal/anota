import Foundation

extension Language {
    /// Line-comment markers for Toggle Line Comment (⌘/): prefix, and suffix for block-only languages.
    public var lineComment: (prefix: String, suffix: String)? {
        switch self {
        case .swift, .javascript, .typescript, .tsx, .json, .c, .cpp, .rust, .go, .java: ("//", "")
        case .python, .yaml, .toml, .shell, .ruby, .dotenv, .powershell: ("#", "")
        case .ini: (";", "")
        case .sql: ("--", "")
        case .batch: ("REM", "")
        case .html, .xml, .markdown: ("<!--", "-->")
        case .css: ("/*", "*/")
        case .plain, .log, .csv, .tsv, .jsonl, .sqlite, .excel: nil
        }
    }
}

/// Pure line edits behind the VS Code editing shortcuts. Each works on the full lines touched by a
/// selection (`block`: text of those lines, newlines included) and returns the replacement.
public enum LineEdits {
    /// ⌘/: comment every non-blank line at the block's common indent, or uncomment if all are commented.
    public static func toggleComment(_ block: String, prefix: String, suffix: String = "") -> String {
        var lines = block.components(separatedBy: "\n")
        let trailingNewline = lines.last == ""
        if trailingNewline { lines.removeLast() }
        let body = lines.filter { !$0.allSatisfy(\.isWhitespace) }
        guard !body.isEmpty else { return block }
        func split(_ l: String) -> (indent: Substring, rest: Substring) {
            let i = l.firstIndex { $0 != " " && $0 != "\t" } ?? l.endIndex
            return (l[..<i], l[i...])
        }
        let commented = body.allSatisfy { split($0).rest.hasPrefix(prefix) && (suffix.isEmpty || split($0).rest.hasSuffix(suffix)) }
        let indent = body.map { split($0).indent }.min { $0.count < $1.count } ?? ""
        let out = lines.map { line -> String in
            guard !line.allSatisfy(\.isWhitespace) else { return line }
            if commented {
                let (ind, rest) = split(line)
                var r = rest.dropFirst(prefix.count)
                if r.hasPrefix(" ") { r = r.dropFirst() }
                if !suffix.isEmpty {
                    r = r.dropLast(suffix.count)
                    if r.hasSuffix(" ") { r = r.dropLast() }
                }
                return String(ind) + r
            }
            let rest = line.dropFirst(indent.count)
            return String(indent) + prefix + " " + rest + (suffix.isEmpty ? "" : " " + suffix)
        }
        return out.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    /// ⌘] / ⌘[: indent or outdent each line by `unit` (outdent removes up to one unit of leading space/tab).
    public static func indent(_ block: String, unit: String = "    ", outdent: Bool = false) -> String {
        var lines = block.components(separatedBy: "\n")
        let trailingNewline = lines.last == ""
        if trailingNewline { lines.removeLast() }
        let out = lines.map { line -> String in
            if !outdent { return line.isEmpty ? line : unit + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, unit.count)))
        }
        return out.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }
}
