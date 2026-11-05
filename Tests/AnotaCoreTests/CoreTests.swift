import Foundation
import Testing
@testable import AnotaCore

@Test func everyLanguageRegexCompiles() {
    for lang in Language.allCases where lang != .plain {
        let h = Highlighter(lang)
        #expect(h.usesTreeSitter || h.groupCount == lang.rules.count, "\(lang)")
    }
}

@Test func leftmostTokenWins() {
    let text = #"val s = "// no" // yes"#  // regex lexer (Java/Kotlin rules)
    let toks = Highlighter(.java).tokens(in: text)
    let ns = text as NSString
    let pairs = toks.map { (ns.substring(with: $0.range), $0.token) }
    #expect(pairs.contains { $0 == ("val", .keyword) })
    #expect(pairs.contains { $0 == (#""// no""#, .string) })
    #expect(pairs.contains { $0 == ("// yes", .comment) })
}

@Test func jsonKeysVsStrings() {
    let text = #"{"a": "b", "n": 1.5e3, "t": true}"#
    let ns = text as NSString
    let pairs = Highlighter(.json).tokens(in: text).map { (ns.substring(with: $0.range), $0.token) }
    #expect(pairs.contains { $0 == (#""a""#, .key) })
    #expect(pairs.contains { $0 == (#""b""#, .string) })
    #expect(pairs.contains { $0 == ("1.5e3", .number) })
    #expect(pairs.contains { $0 == ("true", .keyword) })
}

@Test func detectLanguage() {
    #expect(Language.detect(URL(filePath: "/x/a.swift")) == .swift)
    #expect(Language.detect(URL(filePath: "/x/.env.local")) == .ini)
    #expect(Language.detect(URL(filePath: "/x/Cargo.toml")) == .toml)
    #expect(Language.detect(nil) == .plain)
}

@Test func lineEndingsRoundTrip() throws {
    let f = try TextFile.decode(Data("a\r\nb\r\n".utf8))
    #expect(f.text == "a\nb\n")
    #expect(f.lineEnding == .crlf)
    #expect(try f.encoded() == Data("a\r\nb\r\n".utf8))
}

@Test func encodings() throws {
    let utf16 = "héllo".data(using: .utf16)!  // includes BOM
    #expect(try TextFile.decode(utf16).text == "héllo")
    let latin1 = Data([0x63, 0x61, 0x66, 0xE9])  // "café" in Latin-1, invalid UTF-8
    let f = try TextFile.decode(latin1)
    #expect(f.text == "café" && f.encoding == .isoLatin1)
    #expect(try TextFile.decode(Data([0xEF, 0xBB, 0xBF, 0x41])).text == "A")
    #expect(throws: TextFile.Failure.binary) { try TextFile.decode(Data([0x41, 0x00, 0x42])) }
    #expect(throws: TextFile.Failure.unrepresentable) {
        try TextFile(text: "日本", encoding: .isoLatin1).encoded()
    }
}

@Test func lineNumbers() {
    let s = "a\nb\nc" as NSString
    #expect(lineNumber(in: s, at: 0) == 1)
    #expect(lineNumber(in: s, at: 2) == 2)
    #expect(lineNumber(in: s, at: 5) == 3)
}

@Test func sessionRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "anota-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionStore(dir: dir)
    let dirty = UUID(), clean = UUID()
    func tab(_ id: UUID, _ isDirty: Bool) -> Session.Tab {
        .init(id: id, path: isDirty ? nil : "/tmp/x.txt", dirty: isDirty, encoding: String.Encoding.utf8.rawValue,
              lineEnding: .lf, language: .plain, selection: 3, diskDate: nil)
    }
    var s = Session(tabs: [tab(dirty, true), tab(clean, false)],
                    groups: [.init(tabs: [dirty, clean], active: clean)],
                    focused: 0, root: "/tmp", verticalTabs: true, wrap: false)
    try store.save(s, changed: [dirty: "unsaved ✓"])
    let loaded = try #require(store.load())
    #expect(loaded.session == s)
    #expect(loaded.texts == [dirty: "unsaved ✓"])

    // Saving again without changes keeps the dirty text; once clean, its file is removed.
    try store.save(s, changed: [:])
    #expect(store.load()?.texts == [dirty: "unsaved ✓"])
    s.tabs[0].dirty = false
    try store.save(s, changed: [:])
    #expect(store.load()?.texts == [:])
}

private func pairs(_ lang: Language, _ text: String) -> [(String, Token)] {
    let ns = text as NSString
    return Highlighter(lang).tokens(in: text).map { (ns.substring(with: $0.range), $0.token) }
}

@Test func treeSitterLanguages() {
    let treeSitter: [Language] = [.json, .yaml, .toml, .ini, .python, .javascript, .typescript, .tsx,
                                  .go, .c, .cpp, .rust, .swift]
    for lang in Language.allCases {
        #expect(Highlighter(lang).usesTreeSitter == treeSitter.contains(lang), "\(lang)")
    }
}

@Test func treeSitterYAML() {
    let p = pairs(.yaml, "name: anota # c\nok: true\nn: 3\n")
    #expect(p.contains { $0 == ("name", .key) })
    #expect(p.contains { $0 == ("# c", .comment) })
    #expect(p.contains { $0 == ("true", .keyword) })
    #expect(p.contains { $0 == ("3", .number) })
}

@Test func treeSitterTOML() {
    let p = pairs(.toml, "[server]\nport = 80 # c\nname = \"x\"\n")
    #expect(p.contains { $0 == ("port", .key) })
    #expect(p.contains { $0 == ("80", .number) })
    #expect(p.contains { $0 == ("\"x\"", .string) })
    #expect(p.contains { $0 == ("# c", .comment) })
}

@Test func treeSitterINI() {
    let p = pairs(.ini, "; c\n[sec]\nk = v\n")
    #expect(p.contains { $0.0.hasPrefix("; c") && $0.1 == .comment })
    #expect(p.contains { $0 == ("k", .key) })
}

@Test func treeSitterRangeIsRespected() {
    let text = "{\"a\": 1,\n\"b\": 2}"
    let second = NSRange(location: 9, length: 7)
    let toks = Highlighter(.json).tokens(in: text, range: second)
    #expect(!toks.isEmpty && toks.allSatisfy { NSIntersectionRange($0.range, second).length > 0 })
}

@Test func envFilesHighlightWithoutSection() {
    let p = pairs(.ini, "# c\nexport A=1\nB=\"x\"\n")
    #expect(p.contains { $0.1 == .key && $0.0.hasSuffix("A") })
    #expect(p.contains { $0.1 == .key && $0.0 == "B" })
}

/// One representative snippet per code grammar: keyword, string/number, comment and (where the
/// query has it) function names must come out with the right token.
@Test(arguments: [
    (Language.go, "package main\n// c\nfunc main() { x := \"s\"; _ = 1 }\n",
     [("func", Token.keyword), ("main", .function), ("\"s\"", .string), ("// c", .comment), ("1", .number)]),
    (.c, "#include <x.h>\nint add(int a) { return a + 1; } // c\n",
     [("return", .keyword), ("add", .function), ("int", .type), ("// c", .comment), ("1", .number)]),
    (.cpp, "class A { public: void f(); };\nauto s = \"x\"; // c\n",
     [("class", .keyword), ("A", .type), ("\"x\"", .string), ("// c", .comment)]),
    (.rust, "fn main() { let s = \"x\"; } // c\n",
     [("fn", .keyword), ("let", .keyword), ("main", .function), ("\"x\"", .string), ("// c", .comment)]),
    (.python, "def f(a):\n    return None  # c\n",
     [("def", .keyword), ("f", .function), ("None", .keyword), ("# c", .comment)]),
    (.javascript, "const f = () => 'x'; // c\n",
     [("const", .keyword), ("'x'", .string), ("// c", .comment)]),
    (.typescript, "let n: number = 1; // c\n",
     [("let", .keyword), ("number", .type), ("1", .number), ("// c", .comment)]),
    (.tsx, "const a = <div>hi</div>;\n",
     [("const", .keyword), ("div", .keyword)]),
    (.swift, "let s = \"x\" // c\nfunc f() {}\n",
     [("let", .keyword), ("func", .keyword), ("// c", .comment)]),
])
func codeGrammars(lang: Language, text: String, expected: [(String, Token)]) {
    let p = pairs(lang, text)
    for e in expected {
        #expect(p.contains { $0.0 == e.0 && $0.1 == e.1 }, "\(lang): \(e.0) should be \(e.1); got \(p)")
    }
}
