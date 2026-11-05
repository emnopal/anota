import Foundation

/// Formats a document with the conventional external tool for its language (prettier, gofmt,
/// rustfmt, …), falling back to the built-in JSON formatter. Tools read stdin, write stdout.
public enum CodeFormatter {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noFormatter(language: String, install: [String])
        case toolFailed(tool: String, message: String)
        case timedOut(tool: String)

        public var description: String {
            switch self {
            case .noFormatter(let lang, let install):
                install.isEmpty ? "No formatter for \(lang)."
                    : "No formatter found for \(lang). Install \(install.joined(separator: " or ")) (looked in your login shell PATH)."
            case .toolFailed(let tool, let message): "\(tool) failed: \(message)"
            case .timedOut(let tool): "\(tool) took too long and was stopped."
            }
        }
    }

    public struct Tool: Sendable {
        public let name: String
        let executable: String  // looked up on the search path
        let arguments: @Sendable (_ path: String) -> [String]
    }

    /// Candidate tools in priority order. `path` is the file path (or a placeholder name with the
    /// right extension) so tools can pick their parser and find project config (.prettierrc, rustfmt.toml…).
    public static func tools(for language: Language) -> [Tool] {
        let prettier = Tool(name: "prettier", executable: "prettier") { ["--stdin-filepath", $0] }
        switch language {
        case .javascript, .typescript, .tsx, .css, .html, .markdown, .yaml, .json:
            return [prettier]
        case .go: return [Tool(name: "gofmt", executable: "gofmt") { _ in [] }]
        case .rust: return [Tool(name: "rustfmt", executable: "rustfmt") { _ in ["--emit", "stdout", "--edition", "2021"] }]
        case .c, .cpp: return [Tool(name: "clang-format", executable: "clang-format") { ["--assume-filename=\($0)"] }]
        case .swift:
            return [Tool(name: "swift-format", executable: "swift-format") { ["format", "--assume-filename", $0] },
                    Tool(name: "swift-format (Xcode)", executable: "xcrun") { ["swift-format", "format", "--assume-filename", $0] }]
        case .python:
            return [Tool(name: "ruff", executable: "ruff") { ["format", "--stdin-filename", $0, "-"] },
                    Tool(name: "black", executable: "black") { ["-q", "--stdin-filename", $0, "-"] }]
        case .toml: return [Tool(name: "taplo", executable: "taplo") { _ in ["fmt", "-"] }]
        case .shell: return [Tool(name: "shfmt", executable: "shfmt") { ["-filename", $0] }]
        case .xml: return [Tool(name: "xmllint", executable: "xmllint") { _ in ["--format", "-"] }]
        default: return []
        }
    }

    public static func hasBuiltin(_ language: Language) -> Bool { language == .json }

    /// Returns the formatted text and the name of what formatted it.
    public static func format(_ text: String, language: Language, fileURL: URL?, searchPath: String,
                              timeout: TimeInterval = 10) async throws -> (text: String, tool: String) {
        let path = fileURL?.path ?? "untitled.\(placeholderExtension(language))"
        let dir = fileURL?.deletingLastPathComponent()
        for tool in tools(for: language) {
            guard let exe = find(tool.executable, in: searchPath) else { continue }
            let out = try await run(exe, tool.arguments(path), input: text, searchPath: searchPath,
                                    directory: dir, timeout: timeout, name: tool.name)
            return (out, tool.name)
        }
        if hasBuiltin(language) {
            do {
                return (JSON.format(try JSON.parse(text)) + "\n", "built-in JSON formatter")
            } catch let e as ParseError {
                throw Failure.toolFailed(tool: "JSON formatter", message: e.description)
            }
        }
        throw Failure.noFormatter(language: language.displayName, install: tools(for: language).map(\.name))
    }

    public static func find(_ executable: String, in searchPath: String) -> URL? {
        for dir in searchPath.split(separator: ":") where !dir.isEmpty {
            let url = URL(filePath: String(dir)).appending(path: executable)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// PATH from the user's login shell (GUI apps start with a minimal PATH), plus common tool dirs.
    /// Computed once.
    public static let loginShellPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin", "\(home)/go/bin",
                     "\(home)/.local/bin", "/usr/bin", "/bin"]
        var dirs: [String] = []
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let out = try? runSync(URL(filePath: shell), ["-l", "-c", "printf %s \"$PATH\""], input: "",
                                  environment: nil, directory: nil, timeout: 3, name: "shell") {
            dirs = out.split(separator: ":").map(String.init)
        }
        for d in extra where !dirs.contains(d) { dirs.append(d) }
        return dirs.joined(separator: ":")
    }()

    private static func placeholderExtension(_ language: Language) -> String {
        switch language {
        case .javascript: "js"
        case .typescript: "ts"
        case .markdown: "md"
        case .python: "py"
        case .rust: "rs"
        case .shell: "sh"
        case .yaml: "yaml"
        default: language.rawValue
        }
    }

    private static func run(_ exe: URL, _ args: [String], input: String, searchPath: String, directory: URL?,
                            timeout: TimeInterval, name: String) async throws -> String {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath  // e.g. prettier's `#!/usr/bin/env node` needs node on PATH
        let result = await Task.detached {
            Result { try runSync(exe, args, input: input, environment: env, directory: directory, timeout: timeout, name: name) }
        }.value
        let out = try result.get()
        // A formatter printing nothing for non-empty input is a failure, never "the file is now empty".
        if out.isEmpty && !input.isEmpty { throw Failure.toolFailed(tool: name, message: "produced no output") }
        return out
    }

    /// stdin/stdout/stderr go through temp files: no pipe buffers to deadlock on.
    /// ponytail: polls for exit every 20ms; fine for one-off formatter runs.
    static func runSync(_ exe: URL, _ args: [String], input: String, environment: [String: String]?,
                        directory: URL?, timeout: TimeInterval, name: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "anota-fmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let inURL = tmp.appending(path: "in"), outURL = tmp.appending(path: "out"), errURL = tmp.appending(path: "err")
        try Data(input.utf8).write(to: inURL)
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)

        let p = Process()
        p.executableURL = exe
        p.arguments = args
        if let environment { p.environment = environment }
        if let directory, FileManager.default.fileExists(atPath: directory.path) { p.currentDirectoryURL = directory }
        p.standardInput = try FileHandle(forReadingFrom: inURL)
        p.standardOutput = try FileHandle(forWritingTo: outURL)
        p.standardError = try FileHandle(forWritingTo: errURL)
        do { try p.run() } catch { throw Failure.toolFailed(tool: name, message: error.localizedDescription) }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline {
                p.terminate()
                p.waitUntilExit()
                throw Failure.timedOut(tool: name)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let out = String(decoding: (try? Data(contentsOf: outURL)) ?? Data(), as: UTF8.self)
        guard p.terminationStatus == 0 else {
            let err = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.toolFailed(tool: name, message: err.isEmpty ? "exit code \(p.terminationStatus)" : String(err.prefix(500)))
        }
        return out
    }
}

/// The smallest single replacement turning `old` into `new` (common prefix/suffix trimmed, UTF-16),
/// so applying a reformat keeps the cursor and scroll position where nothing changed.
public func minimalEdit(from old: String, to new: String) -> (range: NSRange, replacement: String)? {
    let a = Array(old.utf16), b = Array(new.utf16)
    guard a != b else { return nil }
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
    // Don't split a surrogate pair at either edge.
    // (prefix/suffix units are identical in both strings, so checking `a` suffices.)
    while prefix > 0, UTF16.isLeadSurrogate(a[prefix - 1]) { prefix -= 1 }
    while suffix > 0, UTF16.isTrailSurrogate(a[a.count - suffix]) { suffix -= 1 }
    let replacement = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
    return (NSRange(location: prefix, length: a.count - suffix - prefix), replacement)
}
