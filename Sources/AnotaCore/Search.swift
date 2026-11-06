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
    public var captures: [NSRange] = []

    public func replacement(in text: String, options: SearchOptions, template: String) throws -> String {
        let re = try options.compile()
        var ranges = captures.isEmpty ? [range] : captures
        let match = ranges.withUnsafeMutableBufferPointer {
            NSTextCheckingResult.regularExpressionCheckingResult(ranges: $0.baseAddress!, count: $0.count, regularExpression: re)
        }
        return options.replacement(for: match, in: text, with: template, using: re)
    }
}

public struct FileMatches: Sendable, Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let matches: [LineMatch]
    public var text: String = ""

    public func replacing(options: SearchOptions, template: String) throws -> String {
        let out = NSMutableString(string: text)
        for match in matches.reversed() {
            out.replaceCharacters(in: match.range, with: try match.replacement(in: text, options: options, template: template))
        }
        return out as String
    }
}

public struct SearchReport: Sendable {
    public let files: [FileMatches]
    public let truncated: Bool
}

public enum FileSearch {
    public static let defaultExcludes = [".git", "node_modules", ".build", "build", "dist", ".DS_Store", "*.min.js"]

    public static func matches(in text: String, _ re: NSRegularExpression, limit: Int = 10_000) -> [LineMatch] {
        scan(text, re, limit: limit).matches
    }

    private static func scan(_ text: String, _ re: NSRegularExpression, limit: Int) -> (matches: [LineMatch], truncated: Bool) {
        let ns = text as NSString
        var truncated = false
        var line = 1, scanned = 0
        var cachedLine = NSRange(location: 0, length: 0)
        let deadline = Date().addingTimeInterval(2)
        var out: [LineMatch] = []
        re.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard out.count < max(0, limit), !Task.isCancelled, Date() < deadline else { truncated = true; stop.pointee = true; return }
            guard let m, m.range.length > 0 else { return }
            line += lineCount(ns, from: scanned, to: m.range.location)
            scanned = m.range.location
            if !NSLocationInRange(m.range.location, cachedLine) {
                cachedLine = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
            }
            let start = max(cachedLine.location, m.range.location - 200)
            let lr = NSRange(location: start, length: min(NSMaxRange(cachedLine), m.range.location + 500) - start)
            let lineText = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            let inLine = NSRange(location: m.range.location - lr.location,
                                 length: min(m.range.length, (lineText as NSString).length - (m.range.location - lr.location)))
            out.append(LineMatch(line: line, lineText: lineText, rangeInLine: inLine, range: m.range, captures: (0..<m.numberOfRanges).map { m.range(at: $0) }))
        }
        return (out, truncated)
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
        try await report(root: root, options: options, include: include, exclude: exclude, limit: limit).files
    }

    public static func report(root: URL, options: SearchOptions, include: [String], exclude: [String], limit: Int = 5000) async throws -> SearchReport {
        let re = try options.compile()
        let excludes = exclude + defaultExcludes
        let worker = Task.detached { () throws -> SearchReport in
            var truncated = false
            var results: [FileMatches] = [], remaining = max(0, limit)
            let fm = FileManager.default
            let root = root.resolvingSymlinksInPath().standardizedFileURL
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]) else { return SearchReport(files: [], truncated: false) }
            let deadline = Date().addingTimeInterval(5)
            while remaining > 0, let url = e.nextObject() as? URL {
                try Task.checkCancellation()
                if Date() > deadline { truncated = true; break }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey])
                let rel = String(url.path.dropFirst(root.path.count + 1))
                if values?.isSymbolicLink == true || matchesGlob(rel, excludes) {
                    e.skipDescendants(); continue
                }
                guard url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"), values?.isDirectory != true,
                      (values?.fileSize ?? 0) < 5_000_000, include.isEmpty || matchesGlob(rel, include),
                      let file = try? TextFile.read(url) else { continue }
                let scanned = scan(file.text, re, limit: remaining)
                truncated = truncated || scanned.truncated
                let found = scanned.matches
                if !found.isEmpty { results.append(FileMatches(url: url, matches: found, text: file.text)); remaining -= found.count }
            }
            return SearchReport(files: results.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }, truncated: truncated || remaining == 0)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
