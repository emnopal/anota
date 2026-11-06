import Foundation
import Testing
@testable import AnotaCore

@Test func fuzzyPathsAndBoundaries() {
    #expect(FuzzyMatcher.score("s/edv", in: "Sources/EditorView.swift") != nil)
    #expect(FuzzyMatcher.score("xyz", in: "EditorView.swift") == nil)
    #expect(FuzzyMatcher.score("EV", in: "EditorView.swift") != nil)
    #expect(FuzzyMatcher.score("editor", in: "editor.swift")! > FuzzyMatcher.score("editor", in: "some/extremely/long/editor.swift")!)
}
@Test func mixedBracketMatchingAndBounds() {
    #expect(BracketMatch.ranges(in: "{[()]}" as NSString, caret: 1).map(\.location) == [0, 5])
    #expect(BracketMatch.ranges(in: "{[)]}" as NSString, caret: 1).isEmpty)
    #expect(BracketMatch.ranges(in: "()" as NSString, caret: 2).map(\.location) == [1, 0])
    #expect(BracketMatch.ranges(in: "(   )" as NSString, caret: 1, limit: 2).isEmpty)
    #expect(BracketMatch.ranges(in: "" as NSString, caret: 0).isEmpty)
}
@Test func markdownTasksHighlightAndEscaping() {
    let html = MarkdownHTML.page("- [x] done\n- [ ] todo\n\n```swift\nlet value = 42\n```\n\n<script>bad()</script>")
    #expect(html.contains("type=\"checkbox\" disabled checked"))
    #expect(html.contains("type=\"checkbox\" disabled>"))
    #expect(html.contains("hljs-keyword"))
    #expect(html.contains("&lt;script&gt;"))
    #expect(!html.contains("<script>"))
    #expect(!MarkdownHTML.highlightingScript.isEmpty)
}
@Test func markdownListContinuation() {
    #expect(MarkdownEditing.continuation("  - [x] done") == "  - [ ] ")
    #expect(MarkdownEditing.continuation("12. item") == "13. ")
    #expect(MarkdownEditing.continuation("- ") == "")
    #expect(MarkdownEditing.continuation("plain text") == nil)
}
@Test func lspFramesSplitAndCoalesced() throws {
    let body = Data("{\"value\":\"日本語\"}".utf8)
    let framed = LSPFraming.frame(body)
    var buffer = Data(framed.prefix(17))
    #expect(try LSPFraming.take(from: &buffer) == nil)
    buffer.append(framed.dropFirst(17)); buffer.append(framed)
    #expect(try LSPFraming.take(from: &buffer) == body)
    #expect(try LSPFraming.take(from: &buffer) == body)
    #expect(buffer.isEmpty)
    buffer = Data("Content-Length: -1\r\n\r\n".utf8)
    #expect(throws: LSPFraming.Failure.self) { try LSPFraming.take(from: &buffer) }
}
@Test func sharedWalkerSkipsExcludedAndSymlink() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appending(path: "node_modules"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appending(path: "visible.txt"))
    try Data().write(to: root.appending(path: "node_modules/hidden.txt"))
    try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: root.deletingLastPathComponent())
    #expect(FileSearch.files(root: root).map(\.lastPathComponent) == ["visible.txt"])
}

@Test func detectsIndentation() {
    #expect(Indentation.detect("func f() {\n  first()\n    nested()\n}") == "  ")
    #expect(Indentation.detect("root\n\tchild\n\tother") == "\t")
    #expect(Indentation.detect("no indent") == nil)
}

@Test func explicitUTF16WithoutBOM() throws {
    let data = Data([0x41, 0x00, 0x0D, 0x00, 0x0A, 0x00])
    let file = try TextFile.decode(data, encoding: .utf16LittleEndian)
    #expect(file.text == "A\n")
    #expect(file.lineEnding == .crlf)
    #expect(file.encoding == .utf16LittleEndian)
}

@Test func relativePathsResolveMacOSTemporaryAlias() {
    let root = URL(filePath: "/tmp/anota-verification")
    let file = URL(filePath: "/private/tmp/anota-verification/folder/test.swift")
    #expect(FileSearch.relativePath(file, root: root) == "folder/test.swift")
}
