import Foundation
import Testing
@testable import AnotaCore

@Test func auditUniqueSQLColumnNames() throws {
    let db = try SQLiteDB(path: nil)
    try db.importTable(DataTable(columns: ["a", "a", "a_2"], rows: [["1", "2", "3"]]), as: "data")
    #expect(try db.query("SELECT * FROM data").rows.count == 1)
}

@Test func auditQuotedEmptyCSVRecord() {
    let t = CSV.parse("value\n\"\"\n", delimiter: ",")
    #expect(t.rows.count == 1)
}

@Test func auditExcel1904Dates() throws {
    let sheets = try XLSX.read(fixture("date1904"))
    let values = sheets.flatMap { $0.table.columns + $0.table.rows.flatMap { $0.compactMap { $0 } } }
    #expect(values.contains("1904-01-02"))
}

@Test func auditMalformedSheetReportsError() {
    #expect(throws: (any Error).self) { try XLSX.read(fixture("broken")) }
}

@Test func auditSearchDoesNotReadOutsideRoot() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let root = base.appendingPathComponent("root")
    defer { try? FileManager.default.removeItem(at: base) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let outside = base.appendingPathComponent("outside.txt")
    try "AUDIT_OUTSIDE_TOKEN".write(to: outside, atomically: true, encoding: .utf8)
    let link = root.appending(path: "linked.txt")
    try? FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    var o = SearchOptions(); o.query = "AUDIT_OUTSIDE_TOKEN"
    let found = try await FileSearch.search(root: root, options: o, include: [], exclude: [])
    #expect(found.isEmpty)
}

@Test func auditSearchLimitIsBounded() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try String(repeating: "needle\n", count: 20_000).write(to: root.appending(path: "many.txt"), atomically: true, encoding: .utf8)
    var o = SearchOptions(); o.query = "needle"
    let report = try await FileSearch.report(root: root, options: o, include: [], exclude: [], limit: 5)
    #expect(report.truncated)
    let found = report.files
    #expect(found.reduce(0) { $0 + $1.matches.count } <= 5)
}

@Test func auditNegativeSharedStringIndex() throws {
    #expect(throws: (any Error).self) { try XLSX.read(fixture("negative")) }
}


private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/" + name + ".xlsx")
}

@Test func markdownEscapesActiveContent() {
    let html = MarkdownHTML.page("<script>alert(1)</script>\n\n```html\n<b>& test</b>\n```\n\n[x](javascript:alert(1))")
    #expect(!html.contains("<script>"))
    #expect(!html.contains("href=\"javascript:"))
    #expect(html.replacingOccurrences(of: #"<span[^>]*>|</span>"#, with: "", options: .regularExpression).contains("&lt;b&gt;&amp; test&lt;/b&gt;"))
    #expect(html.contains("Content-Security-Policy"))
}

@Test func csvEmptyRecordsStayDistinct() {
    #expect(CSV.parse("value\n\n\"\"\n", delimiter: ",").rows == [[""]])
    #expect(CSV.parse("a,b\n,\n", delimiter: ",").rows == [["", ""]])
}

@Test func sqlColumnCaseCollisions() throws {
    let names = SQLiteDB.uniqueNames(["a", "A", "a_2", "A_2"])
    #expect(Set(names.map { $0.lowercased() }).count == 4)
    #expect(XLSX.date(1.5, date1904: true) == "1904-01-02 12:00:00")
    #expect(XLSX.date(1) == "1900-01-01")
    #expect(XLSX.date(61) == "1900-03-01")
}

@Test func sqlDeadlineInterruptsWork() throws {
    let db = try SQLiteDB(path: nil)
    #expect(throws: SQLiteDB.Failure.self) {
        try db.query("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n", timeout: 0.01)
    }
    #expect(try db.query("SELECT 42").rows == [["42"]])
}

@Test func savingRejectsExternalChanges() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try TextFile(text: "original").write(to: url)
    let revision = try FileRevision.read(url)
    try TextFile(text: "external").write(to: url)
    #expect(throws: TextFile.Failure.changedOnDisk) { try TextFile(text: "mine").write(to: url, matching: revision) }
    #expect(try TextFile.read(url).text == "external")
}

@Test func replacementPreviewMatchesAppliedCaptures() throws {
    var options = SearchOptions()
    options.query = "(cat)"; options.regex = true; options.preserveCase = true
    let text = "CAT cat"
    let matches = FileSearch.matches(in: text, try options.compile())
    let file = FileMatches(url: URL(fileURLWithPath: "/tmp/unused"), matches: matches, text: text)
    #expect(try matches[0].replacement(in: text, options: options, template: "$1s") == "CATS")
    #expect(try file.replacing(options: options, template: "$1s") == "CATS cats")
    #expect(try file.replacing(options: options, template: "") == " ")
    let limited = FileMatches(url: file.url, matches: Array(matches.prefix(1)), text: text)
    #expect(try limited.replacing(options: options, template: "dog") == "DOG cat")
}

@Test func cancelledSQLStopsAndConnectionRecovers() async throws {
    let db = try SQLiteDB(path: nil)
    let worker = Task.detached {
        try db.query("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n")
    }
    try await Task.sleep(for: .milliseconds(30))
    worker.cancel()
    db.interrupt()
    do { _ = try await worker.value; Issue.record("Cancelled SQL completed") } catch { }
    #expect(try db.query("SELECT 1").rows == [["1"]])
}

@Test func searchSnippetsBoundLongLines() throws {
    let text = String(repeating: "needle ", count: 20_000)
    let matches = FileSearch.matches(in: text, try NSRegularExpression(pattern: "needle"), limit: 5)
    #expect(matches.count == 5)
    #expect(matches.allSatisfy { ($0.lineText as NSString).length <= 700 })
}

@Test func coordinatedSaveCreatesNewFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try FileRevision.read(url) == .missing)
    try TextFile(text: "new file").write(to: url, matching: .missing)
    #expect(try TextFile.read(url).text == "new file")
}

@Test func largeFolderSearchCancelsPromptly() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = Data(String(repeating: "ordinary text\n", count: 600).utf8)
    for i in 0..<1500 { try contents.write(to: root.appendingPathComponent("file-\(i).txt")) }
    var options = SearchOptions(); options.query = "absent"
    let worker = Task { try await FileSearch.report(root: root, options: options, include: [], exclude: []) }
    try await Task.sleep(for: .milliseconds(20))
    let start = ContinuousClock.now
    worker.cancel()
    do { _ = try await worker.value; Issue.record("Cancelled folder search completed normally") }
    catch is CancellationError { }
    #expect(start.duration(to: .now) < .seconds(2))
}

@Test func pathologicalRegexHonorsProgressDeadline() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try (String(repeating: "a", count: 150_000) + "!").write(to: root.appendingPathComponent("slow.txt"), atomically: true, encoding: .utf8)
    var options = SearchOptions(); options.query = "(a+)+$"; options.regex = true
    let start = ContinuousClock.now
    let report = try await FileSearch.report(root: root, options: options, include: [], exclude: [])
    #expect(report.truncated)
    #expect(report.files.isEmpty)
    #expect(start.duration(to: .now) < .seconds(5))
}
