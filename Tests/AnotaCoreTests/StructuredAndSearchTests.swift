import Foundation
import Testing
@testable import AnotaCore

@Test func jsonKeepsOrderAndRanges() throws {
    let text = #"{"z": 1, "a": [true, null, "x\n"], "m": {"k": -2.5e1}}"#
    let n = try JSON.parse(text)
    #expect(n.children.map(\.key) == ["z", "a", "m"])
    let z = n.children[0]
    #expect((text as NSString).substring(with: z.range!) == "1")
    #expect(n.children[1].children[2].value == .string("x\n"))
    #expect(JSON.format(n, indent: 0) == #"{"z":1,"a":[true,null,"x\n"],"m":{"k":-2.5e1}}"#)
    #expect(try JSON.parse(JSON.format(n)) .children.map(\.key) == ["z", "a", "m"])
}

@Test func jsonToleratesCommentsAndTrailingCommas() throws {
    let n = try JSON.parse("// c\n{\"a\": 1, /* x */ \"b\": [1,2,],}\n")
    #expect(n.children.count == 2)
    #expect(n.children[1].children.count == 2)
}

@Test func jsonErrorsHaveLocation() {
    #expect(throws: ParseError(message: "Expected “,” or “}”", line: 2, column: 2)) {
        try JSON.parse("{\"a\": 1\n \"b\": 2}")
    }
    #expect(throws: ParseError.self) { try JSON.parse("{\"a\": tru}") }
    #expect(throws: ParseError.self) { try JSON.parse("[1] 2") }
    #expect(throws: ParseError.self) { try JSON.parse("\"open") }
}

@Test func jsonUnicodeEscapes() throws {
    #expect(try JSON.parse(#""é😀""#).value == .string("é😀"))
    #expect(JSON.quote("a\"b\u{1}") == #""a\"b\u0001""#)
}

@Test func treePathsAndFilter() throws {
    let tree = TreeItem.build(try JSON.parse(#"{"users": [{"first name": "Ann", "age": 3}], "ok": true}"#))
    let user = tree.children![0].children![0]
    #expect(user.id == "$.users[0]")
    #expect(user.children!.map(\.id) == [#"$.users[0]["first name"]"#, "$.users[0].age"])
    let f = try #require(tree.filtered("ann"))
    #expect(f.children!.count == 1)  // "ok" dropped, path to Ann kept
    #expect(tree.filtered("nothing-here") == nil)
    #expect(tree.containerIDs == ["$", "$.users", "$.users[0]"])
}

@Test func iniAndEnv() {
    let n = INI.parse("top=1\n; comment\n[server]\nhost = \"localhost\"\nport: 80\n\nexport TOKEN='abc'\n")
    #expect(n.children.map(\.key) == ["top", "server"])
    #expect(n.children[1].children.map(\.key) == ["host", "port", "TOKEN"])
    #expect(n.children[1].children[0].value == .string("localhost"))
    #expect(n.children[1].children[2].value == .string("abc"))
}

@Test func plistParses() throws {
    let xml = #"<?xml version="1.0"?><plist version="1.0"><dict><key>b</key><true/><key>a</key><array><integer>1</integer><string>s</string></array></dict></plist>"#
    let n = try Plist.parse(xml)
    #expect(n.children.map(\.key) == ["a", "b"])
    #expect(n.children[1].value == .bool(true))
    #expect(n.children[0].children.map(\.value) == [.number("1"), .string("s")])
}

@Test func searchOptions() throws {
    var o = SearchOptions()
    o.query = "foo"
    #expect(try o.replaceAll(in: "foo Foo food", with: "bar").1 == 3)
    o.wholeWord = true
    #expect(try o.replaceAll(in: "foo Foo food", with: "bar").0 == "bar bar food")
    o.preserveCase = true
    #expect(try o.replaceAll(in: "foo Foo FOO", with: "bar").0 == "bar Bar BAR")
    o = SearchOptions()
    o.query = #"(\w+)@(\w+)"#
    o.regex = true
    #expect(try o.replaceAll(in: "a@b c@d", with: "$2.$1").0 == "b.a d.c")
    o.query = "a.b"
    o.regex = false
    #expect(try o.replaceAll(in: "a.b axb", with: "!").0 == "! axb")
}

@Test func lineMatches() throws {
    var o = SearchOptions()
    o.query = "x"
    let m = FileSearch.matches(in: "ax\nb\n  xx", try o.compile())
    #expect(m.map(\.line) == [1, 3, 3])
    #expect(m[1].lineText == "  xx" && m[1].rangeInLine == NSRange(location: 2, length: 1))
}

@Test func globs() {
    #expect(FileSearch.matchesGlob("src/a.swift", ["*.swift"]))
    #expect(FileSearch.matchesGlob("x/node_modules", ["node_modules"]))
    #expect(!FileSearch.matchesGlob("src/a.ts", ["*.swift"]))
    #expect(FileSearch.matchesGlob("src/a.ts", ["src/*"]))
    #expect(FileSearch.globs(" *.a, ,*.b ") == ["*.a", "*.b"])
}

@Test func searchFolder() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "anota-search-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir.appending(path: "node_modules"), withIntermediateDirectories: true)
    try "needle\nhay".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "needle".write(to: dir.appending(path: "b.md"), atomically: true, encoding: .utf8)
    try "needle".write(to: dir.appending(path: "node_modules/c.txt"), atomically: true, encoding: .utf8)
    try Data([0, 1, 2]).write(to: dir.appending(path: "bin.dat"))
    var o = SearchOptions()
    o.query = "needle"
    let all = try await FileSearch.search(root: dir, options: o, include: [], exclude: [])
    #expect(all.map(\.url.lastPathComponent) == ["a.txt", "b.md"])
    let txt = try await FileSearch.search(root: dir, options: o, include: ["*.txt"], exclude: [])
    #expect(txt.map(\.url.lastPathComponent) == ["a.txt"])
}

@Test func yamlKeepsOrderAndTypes() throws {
    let n = try YAML.parse("b: 1\na:\n  - true\n  - ~\n  - \"2\"\n  - hi\n")
    #expect(n.children.map(\.key) == ["b", "a"])
    #expect(n.children[0].value == .number("1"))
    #expect(n.children[1].children.map(\.value) == [.bool(true), .null, .string("2"), .string("hi")])
    #expect(throws: ParseError.self) { try YAML.parse("a: [1, 2\nb: 3") }
}

@Test func tomlParses() throws {
    let n = try TOML.parse("title = \"x\"\n[server]\nport = 8080\n")
    #expect(n.children.first { $0.key == "server" }?.children.first?.value == .number("8080"))
    #expect(throws: ParseError.self) { try TOML.parse("a = \n") }
}

@Test func markdownRendersHTML() {
    let html = MarkdownHTML.page("# Hi\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
    #expect(html.contains("<h1>Hi</h1>"))
    #expect(html.contains("<table>"))
}
