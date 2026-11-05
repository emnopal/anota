import Foundation
import Testing
@testable import AnotaCore

/// A temp dir holding fake formatter executables named like the real ones.
private func fakeTools(_ scripts: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "anota-tools-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, body) in scripts {
        let url = dir.appending(path: name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    return dir
}

@Test func externalToolFormatsViaStdin() async throws {
    let dir = try fakeTools(["gofmt": "tr a-z A-Z"])
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = try await CodeFormatter.format("func main() {}\n", language: .go, fileURL: nil, searchPath: dir.path + ":/usr/bin:/bin")
    #expect(r.text == "FUNC MAIN() {}\n")
    #expect(r.tool == "gofmt")
}

@Test func toolGetsFilePathAndPriority() async throws {
    // ruff is preferred over black; it receives --stdin-filename <path>.
    let dir = try fakeTools(["ruff": "echo \"$@\"", "black": "echo black"])
    defer { try? FileManager.default.removeItem(at: dir) }
    let r = try await CodeFormatter.format("x=1", language: .python, fileURL: URL(filePath: "/p/a.py"), searchPath: dir.path + ":/usr/bin:/bin")
    #expect(r.tool == "ruff")
    #expect(r.text == "format --stdin-filename /p/a.py -\n")
}

@Test func toolFailureReportsStderrAndNeverEmpties() async throws {
    let dir = try fakeTools(["rustfmt": "echo 'error: expected item' >&2; exit 1", "gofmt": "cat > /dev/null"])
    defer { try? FileManager.default.removeItem(at: dir) }
    await #expect(throws: CodeFormatter.Failure.toolFailed(tool: "rustfmt", message: "error: expected item")) {
        try await CodeFormatter.format("fn {", language: .rust, fileURL: nil, searchPath: dir.path + ":/usr/bin:/bin")
    }
    await #expect(throws: CodeFormatter.Failure.toolFailed(tool: "gofmt", message: "produced no output")) {
        try await CodeFormatter.format("package x", language: .go, fileURL: nil, searchPath: dir.path + ":/usr/bin:/bin")
    }
}

@Test func toolTimesOut() async throws {
    let dir = try fakeTools(["shfmt": "sleep 5"])
    defer { try? FileManager.default.removeItem(at: dir) }
    await #expect(throws: CodeFormatter.Failure.timedOut(tool: "shfmt")) {
        try await CodeFormatter.format("a", language: .shell, fileURL: nil, searchPath: dir.path + ":/usr/bin:/bin", timeout: 0.3)
    }
}

@Test func builtinJSONAndMissingFormatter() async throws {
    let r = try await CodeFormatter.format(#"{"b":1,"a":[1,2]}"#, language: .json, fileURL: nil, searchPath: "")
    #expect(r.text == "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}\n")
    await #expect(throws: CodeFormatter.Failure.noFormatter(language: "Go", install: ["gofmt"])) {
        try await CodeFormatter.format("x", language: .go, fileURL: nil, searchPath: "")
    }
    await #expect(throws: CodeFormatter.Failure.noFormatter(language: "SQL", install: [])) {
        try await CodeFormatter.format("x", language: .sql, fileURL: nil, searchPath: "")
    }
}

@Test func minimalEdits() {
    #expect(minimalEdit(from: "same", to: "same") == nil)
    let e = minimalEdit(from: "let  x = 1\nok", to: "let x = 1\nok")!
    #expect(e.range == NSRange(location: 4, length: 1) && e.replacement == "")
    let grow = minimalEdit(from: "ab", to: "aXb")!
    #expect(grow.range == NSRange(location: 1, length: 0) && grow.replacement == "X")
    // Never split an emoji's surrogate pair.
    let emoji = minimalEdit(from: "a😀", to: "a😃")!
    #expect(emoji.range == NSRange(location: 1, length: 2) && emoji.replacement == "😃")
    // Applying the edit reproduces the target.
    for (a, b) in [("hello world", "hello brave world"), ("x", ""), ("", "y"), ("aaa", "aa")] {
        let m = minimalEdit(from: a, to: b)!
        #expect((a as NSString).replacingCharacters(in: m.range, with: m.replacement) == b)
    }
}

@Test func loginShellPathHasCommonDirs() {
    #expect(CodeFormatter.loginShellPath.contains("/usr/bin"))
    #expect(CodeFormatter.find("sh", in: "/bin") != nil)
}
