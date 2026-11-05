import Foundation

public struct SearchOptions: Sendable, Equatable {
    public var query = ""
    public var caseSensitive = false
    public var wholeWord = false
    public var regex = false
    public var preserveCase = false
    public init() {}

    public func compile() throws -> NSRegularExpression {
        var pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = #"\b(?:"# + pattern + #")\b"# }
        return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// Replacement text for one match: `$1` templates in regex mode, case-matching when preserveCase.
    public func replacement(for match: NSTextCheckingResult, in text: String, with template: String,
                            using re: NSRegularExpression) -> String {
        var out = regex
            ? re.replacementString(for: match, in: text, offset: 0, template: template)
            : template
        if preserveCase {
            let found = (text as NSString).substring(with: match.range)
            if found == found.uppercased(), found != found.lowercased() { out = out.uppercased() }
            else if found.first?.isUppercase == true { out = out.prefix(1).uppercased() + out.dropFirst() }
            else if found == found.lowercased() { out = out.lowercased() }
        }
        return out
    }

    /// Replace every match; returns the new text and the replacement count.
    public func replaceAll(in text: String, with template: String) throws -> (String, Int) {
        let re = try compile()
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let out = NSMutableString(string: text)
        for m in matches.reversed() {
            out.replaceCharacters(in: m.range, with: replacement(for: m, in: text, with: template, using: re))
        }
        return (out as String, matches.count)
    }
}

public struct LineMatch: Sendable, Identifiable, Equatable {
    public var id: Int { range.location }
    public let line: Int
    public let lineText: String
    public let rangeInLine: NSRange
    public let range: NSRange  // in the whole file
}

public struct FileMatches: Sendable, Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let matches: [LineMatch]
}

public enum FileSearch {
    public static let defaultExcludes = [".git", "node_modules", ".build", "build", "dist", ".DS_Store", "*.min.js"]

    public static func matches(in text: String, _ re: NSRegularExpression) -> [LineMatch] {
        let ns = text as NSString
        var line = 1, scanned = 0
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.range.length > 0 else { return nil }
            line += lineCount(ns, from: scanned, to: m.range.location)
            scanned = m.range.location
            let lr = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
            let lineText = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            let inLine = NSRange(location: m.range.location - lr.location,
                                 length: min(m.range.length, (lineText as NSString).length - (m.range.location - lr.location)))
            return LineMatch(line: line, lineText: lineText, rangeInLine: inLine, range: m.range)
        }
    }

    private static func lineCount(_ ns: NSString, from: Int, to: Int) -> Int {
        var n = 0
        for i in from..<to where ns.character(at: i) == 10 { n += 1 }
        return n
    }

    /// Comma-separated globs. A pattern without "/" matches the file or folder name; otherwise the relative path.
    public static func globs(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func matchesGlob(_ relPath: String, _ patterns: [String]) -> Bool {
        let name = (relPath as NSString).lastPathComponent
        return patterns.contains { p in
            let p = p.hasPrefix("**/") ? String(p.dropFirst(3)) : p
            return fnmatch(p, p.contains("/") ? relPath : name, 0) == 0
        }
    }

    /// Search every text file under `root`. Runs off the main actor; cancellable.
    public static func search(root: URL, options: SearchOptions, include: [String], exclude: [String],
                              limit: Int = 5000) async throws -> [FileMatches] {
        let re = try options.compile()
        let excludes = exclude + defaultExcludes
        let files = await Task.detached { () -> [URL] in
            var out: [URL] = []
            let fm = FileManager.default
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { return [] }
            let rootPath = root.standardizedFileURL.path
            while let url = e.nextObject() as? URL {
                let rel = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if matchesGlob(rel, excludes) {
                    if values?.isDirectory == true { e.skipDescendants() }
                    continue
                }
                guard values?.isDirectory != true, (values?.fileSize ?? 0) < 5_000_000 else { continue }
                if include.isEmpty || matchesGlob(rel, include) { out.append(url) }
            }
            return out
        }.value

        return try await withThrowingTaskGroup(of: FileMatches?.self) { group in
            for url in files {
                group.addTask {
                    try Task.checkCancellation()
                    guard let file = try? TextFile.read(url) else { return nil }  // binary/unreadable
                    let m = matches(in: file.text, re)
                    return m.isEmpty ? nil : FileMatches(url: url, matches: m)
                }
            }
            var results: [FileMatches] = []
            var total = 0
            for try await r in group {
                guard let r else { continue }
                results.append(r)
                total += r.matches.count
                if total >= limit { group.cancelAll(); break }
            }
            return results.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        }
    }
}
