import Foundation
import Testing
@testable import AnotaCore

@Test func csvParsing() {
    let t = CSV.parse("name,note,n\r\n\"Doe, J\",\"said \"\"hi\"\"\nthen left\",3\nAmy,,4,extra\n\n")
    #expect(t.columns == ["name", "note", "n", "column4"])
    #expect(t.rows.count == 2)
    #expect(t.rows[0] == ["Doe, J", "said \"hi\"\nthen left", "3", nil])
    #expect(t.rows[1] == ["Amy", "", "4", "extra"])
}

@Test func csvSniffAndHeaderless() {
    #expect(CSV.sniff("a;b;c\n1;2;3\n") == ";")
    #expect(CSV.sniff("a\tb\n1\t2\n") == "\t")
    let t = CSV.parse("1,2\n3,4\n")
    #expect(t.columns == ["column1", "column2"] && t.rows.count == 2)
    #expect(CSV.parse("", delimiter: ",").rows.isEmpty)
}

@Test func jsonLines() {
    let t = JSONLines.parse("{\"a\":1,\"b\":{\"x\":[1,2]}}\n\nnot json\n{\"c\":null,\"a\":\"s\"}\n")
    #expect(t.columns == ["a", "b", "c"])
    #expect(t.rows == [["1", "{\"x\":[1,2]}", nil], ["s", nil, nil]])
    #expect(t.warnings == ["Line 3: invalid JSON"])
}

@Test func sortOrder() {
    let vals: [String?] = ["10", nil, "9", "b", "a"]
    #expect(vals.sorted(by: DataTable.less) == ["9", "10", "a", "b", nil])
}

@Test func sqliteRoundTrip() throws {
    let path = FileManager.default.temporaryDirectory.appending(path: "anota-\(UUID()).db").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    do {
        let rw = try SQLiteDB(path: path, readOnly: false)
        try rw.exec("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL, pic BLOB); CREATE VIEW names AS SELECT name FROM people;")
        try rw.exec("INSERT INTO people (name, pic) VALUES ('Ada', x'0102'), ('Bob', NULL)")
    }
    let db = try SQLiteDB(path: path)
    let schema = try db.schema()
    #expect(schema.map(\.name) == ["people", "names"])
    #expect(schema[0].columns.map(\.name) == ["id", "name", "pic"])
    #expect(schema[0].columns[0].primaryKey && schema[0].columns[1].notNull)
    let r = try db.query("SELECT * FROM people ORDER BY id")
    #expect(r.columns == ["id", "name", "pic"])
    #expect(r.rows == [["1", "Ada", "<BLOB 2 bytes>"], ["2", "Bob", nil]])
    #expect(try db.query("SELECT * FROM people", limit: 1).truncated)
    // Read-only: writes are refused by SQLite itself.
    #expect(throws: SQLiteDB.Failure.self) { try db.exec("DELETE FROM people") }
    #expect(throws: SQLiteDB.Failure.self) { try db.query("SELEC nope") }
}

@Test func sqlOverImportedTable() throws {
    let mem = try SQLiteDB(path: nil)
    try mem.importTable(CSV.parse("city,pop\nA,10\nB,5\nA,1\n"), as: SQLiteDB.tableName(for: "2026 cities.csv"))
    let r = try mem.query("SELECT city, SUM(pop) FROM t_2026_cities GROUP BY city ORDER BY city")
    #expect(r.rows == [["A", "11"], ["B", "5"]])
    #expect(SQLiteDB.tableName(for: "sales-q1.csv") == "sales_q1")
}

@Test func xlsxReader() throws {
    let url = try #require(Bundle.module.url(forResource: "sample", withExtension: "xlsx", subdirectory: "Fixtures"))
    let sheets = try XLSX.read(url)
    #expect(sheets.map(\.name) == ["People", "Raw"])
    #expect(sheets[0].table.columns == ["name", "born", "ok"])
    #expect(sheets[0].table.rows == [["Ada L.", "2025-11-05", "TRUE"], ["Bob", nil, "FALSE"]])
    #expect(sheets[1].table.columns == ["A", "B", "C"])  // numeric first row → letter headers
    #expect(sheets[1].table.rows == [["1.5", nil, "3"]])  // cached formula value
    #expect(XLSX.column("AB12") == 27 && XLSX.letters(27) == "AB")
    #expect(throws: XLSX.Failure.self) { try XLSX.read(URL(filePath: #filePath)) }
}

@Test func headerToggleAndTypes() {
    let t = CSV.parse("id,price,ok,day,name\n1,2.5,true,2026-01-02,x\n2,3,false,2026-01-03T10:00:00Z,\n")
    #expect(t.hasHeaderRow)
    #expect(t.columnTypes() == [.integer, .decimal, .boolean, .date, .text])
    let off = t.togglingHeader()
    #expect(off.columns == ["column1", "column2", "column3", "column4", "column5"] && off.rows.count == 3)
    #expect(off.togglingHeader() == t)
    #expect(XLSX.letters(0) == DataTable.genericName(0, letters: true))
}

@Test func exportFormats() {
    let t = DataTable(columns: ["a", "b"], rows: [["x,y", nil], ["q\"z", "2"]])
    #expect(t.csv() == "a,b\n\"x,y\",\n\"q\"\"z\",2\n")
    #expect(t.json(rows: [1]) == "[\n  {\"a\": \"q\\\"z\", \"b\": \"2\"}\n]\n")
    #expect(CSV.parse(t.csv()).rows == [["x,y", ""], ["q\"z", "2"]])
}

@Test func sqliteErrorOffsetCountAndIndexes() throws {
    let db = try SQLiteDB(path: nil)
    try db.exec("CREATE TABLE t (a INT, b TEXT); CREATE INDEX t_b ON t(b); INSERT INTO t VALUES (1,'x'),(2,'y');")
    #expect(try db.count("t") == 2)
    #expect(try db.schema().first?.indexes == ["t_b"])
    do {
        _ = try db.query("SELECT a FROM t WHERE nope = 1")
        Issue.record("expected an error")
    } catch let e as SQLiteDB.Failure {
        #expect(e.offset == 22)  // points at `nope`
    }
}

@Test func rainbowColumns() {
    let h = Highlighter(.csv)
    let text = "a,\"b,c\",d\n1,2\n"
    let toks = h.tokens(in: text).map { ((text as NSString).substring(with: $0.range), $0.token) }
    #expect(toks.map(\.0) == ["a", "\"b,c\"", "d", "1", "2"])
    #expect(toks[0].1 == toks[3].1 && toks[1].1 == toks[4].1 && toks[0].1 != toks[1].1)
    #expect(Highlighter(.tsv).tokens(in: "x\ty\n").count == 2)
}

@Test func rowFilter() {
    let t = DataTable(columns: ["a", "b"], rows: [["Café", "x"], ["tea", "cafe"], [nil, "y"]])
    #expect(t.matching("cafe") == [0, 1])
    #expect(t.matching("CAFE", column: 1) == [1])
    #expect(t.matching("  ") == [0, 1, 2])
}
