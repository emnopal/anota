import Foundation

/// A grid of string cells (nil = NULL) shared by every data format.
/// ponytail: fully in memory (fine to a few million cells); stream/paginate if huge files matter.
public struct DataTable: Sendable, Equatable {
    public var columns: [String]
    public var rows: [[String?]]
    /// Problems worth showing (e.g. invalid JSON lines), at most a handful.
    public var warnings: [String] = []
    /// True when `rows` stopped at a row limit.
    public var truncated = false
    /// Whether `columns` came from the data's first row (so the header toggle can undo it).
    public var hasHeaderRow = false
    /// Generic column names when there's no header: `A, B, C…` (spreadsheets) or `column1…` (text formats).
    public var letterNames = false

    public init(columns: [String], rows: [[String?]], warnings: [String] = [], truncated: Bool = false,
                hasHeaderRow: Bool = false, letterNames: Bool = false) {
        self.columns = columns
        self.rows = rows
        self.warnings = warnings
        self.truncated = truncated
        self.hasHeaderRow = hasHeaderRow
        self.letterNames = letterNames
    }

    public static func genericName(_ i: Int, letters: Bool) -> String { letters ? XLSX.letters(i) : "column\(i + 1)" }

    /// "First row is header" toggled: the header goes back into the data, or the first row becomes the header.
    public func togglingHeader() -> DataTable {
        var t = self
        if hasHeaderRow {
            t.rows.insert(columns.map { Optional($0) }, at: 0)
            t.columns = columns.indices.map { Self.genericName($0, letters: letterNames) }
        } else if let first = rows.first {
            t.rows.removeFirst()
            t.columns = first.enumerated().map { i, v in (v?.isEmpty == false ? v! : Self.genericName(i, letters: letterNames)) }
        }
        t.hasHeaderRow.toggle()
        return t
    }

    public enum ColumnType: String, Sendable { case integer, decimal, boolean, date, text, empty
        /// Short glyph for column headers.
        public var glyph: String {
            switch self { case .integer: "#"; case .decimal: "#.#"; case .boolean: "✓"; case .date: "◷"; case .text: "Aa"; case .empty: "∅" }
        }
    }

    /// Guess each column's type from its non-NULL, non-empty values (first 1,000 rows).
    public func columnTypes() -> [ColumnType] {
        columns.indices.map { c in
            let vals = rows.prefix(1_000).compactMap { c < $0.count ? $0[c] : nil }.filter { !$0.isEmpty }
            guard !vals.isEmpty else { return .empty }
            if vals.allSatisfy({ Int($0) != nil }) { return .integer }
            if vals.allSatisfy({ Double($0) != nil }) { return .decimal }
            if vals.allSatisfy({ ["true", "false"].contains($0.lowercased()) }) { return .boolean }
            if vals.allSatisfy({ $0.range(of: #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$"#, options: .regularExpression) != nil }) { return .date }
            return .text
        }
    }

    /// RFC 4180 CSV (fields quoted when needed), header first; NULL → empty field.
    public func csv(rows indexes: [Int]? = nil) -> String {
        func field(_ s: String?) -> String {
            guard let s else { return "" }
            return s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        let body = (indexes ?? Array(rows.indices)).map { rows[$0].map(field).joined(separator: ",") }
        return ([columns.map(field).joined(separator: ",")] + body).joined(separator: "\n") + "\n"
    }

    /// JSON array of objects keyed by column (NULL → null), values as strings.
    public func json(rows indexes: [Int]? = nil) -> String {
        let objs = (indexes ?? Array(rows.indices)).map { r -> String in
            let pairs = columns.enumerated().map { i, c in
                JSON.quote(c) + ": " + ((i < rows[r].count ? rows[r][i] : nil).map(JSON.quote) ?? "null")
            }
            return "  {" + pairs.joined(separator: ", ") + "}"
        }
        return "[\n" + objs.joined(separator: ",\n") + "\n]\n"
    }

    /// Order for sorting a column: numbers numerically, then text (natural order), NULLs last.
    public static func less(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?):
            if let p = Double(x), let q = Double(y) { return p < q }
            return x.localizedStandardCompare(y) == .orderedAscending
        }
    }

    /// Indexes of rows containing `filter` (case/diacritic-insensitive), in one column or any.
    public func matching(_ filter: String, column: Int? = nil) -> [Int] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return Array(rows.indices) }
        func hit(_ v: String?) -> Bool { v?.range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return rows.indices.filter { i in
            if let c = column { return c < rows[i].count && hit(rows[i][c]) }
            return rows[i].contains(where: hit)
        }
    }

    /// Rows as TSV (for copy), header first.
    public func tsv(rows indexes: [Int]? = nil) -> String {
        func cell(_ s: String?) -> String { (s ?? "").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
        let body = (indexes ?? Array(rows.indices)).map { rows[$0].map(cell).joined(separator: "\t") }
        return ([columns.joined(separator: "\t")] + body).joined(separator: "\n")
    }
}

// MARK: CSV / TSV

public enum CSV {
    /// RFC 4180: quoted fields, `""` escapes, newlines inside quotes, CRLF. `delimiter` nil = sniff.
    /// Ragged rows are padded with NULL; a header row is used when it looks like one.
    public static func parse(_ text: String, delimiter: Character? = nil) -> DataTable {
        let d = delimiter ?? sniff(text)
        var records = split(text, d)
        guard !records.isEmpty else { return DataTable(columns: [], rows: []) }
        let width = records.map(\.count).max() ?? 0
        let header: [String]
        let hasHeader = looksLikeHeader(records)
        if hasHeader {
            let first = records.removeFirst()
            header = (0..<width).map { i in i < first.count && !first[i].isEmpty ? first[i] : DataTable.genericName(i, letters: false) }
        } else {
            header = (0..<width).map { DataTable.genericName($0, letters: false) }
        }
        let rows = records.map { r -> [String?] in r.map { Optional($0) } + Array(repeating: nil, count: width - r.count) }
        return DataTable(columns: header, rows: rows, hasHeaderRow: hasHeader)
    }

    /// Most consistent of `,` `;` `\t` `|` over the first lines (outside quotes).
    public static func sniff(_ text: String) -> Character {
        let sample = String(text.prefix(64_000))
        var best: (Character, Int) = (",", -1)
        for c in [",", "\t", ";", "|"] as [Character] {
            let counts = split(sample, c).prefix(50).dropLast().map(\.count)  // last line may be cut off
            guard let first = counts.first, first > 1 else { continue }
            let score = counts.filter { $0 == first }.count * first
            if score > best.1 { best = (c, score) }
        }
        return best.0
    }

    /// Byte-level scanner over UTF-8 (delimiters and quotes are ASCII, so multi-byte text passes through intact).
    /// ~10× faster than iterating Characters on big files.
    static func split(_ text: String, _ delimiter: Character) -> [[String]] {
        let d = delimiter.asciiValue ?? 44
        var records: [[String]] = []
        var t = text
        t.withUTF8 { buf in
            var record: [String] = []
            var field: [UInt8] = []
            var quoted = false, wasQuoted = false, recordQuoted = false
            var i = 0
            let n = buf.count
            func endField() { record.append(String(decoding: field, as: UTF8.self)); field.removeAll(keepingCapacity: true); wasQuoted = false }
            func endRecord() {
                endField()
                if !(record.count == 1 && record[0].isEmpty && !recordQuoted) { records.append(record) }  // skip blank lines
                record = []; recordQuoted = false
            }
            while i < n {
                let c = buf[i]
                if quoted {
                    if c == 34 {  // "
                        if i + 1 < n, buf[i + 1] == 34 { field.append(34); i += 1 } else { quoted = false }
                    } else {
                        field.append(c)
                    }
                } else if c == 34 && field.isEmpty && !wasQuoted {
                    quoted = true; wasQuoted = true; recordQuoted = true
                } else if c == d {
                    endField()
                } else if c == 10 {
                    endRecord()
                } else if c == 13 {
                    endRecord()
                    if i + 1 < n, buf[i + 1] == 10 { i += 1 }
                } else {
                    field.append(c)
                }
                i += 1
            }
            if !field.isEmpty || !record.isEmpty || wasQuoted { endRecord() }
        }
        return records
    }

    /// The first row is a header unless it has a number in it or repeats a name (exports nearly always have one).
    static func looksLikeHeader(_ records: [[String]]) -> Bool {
        let first = records[0]
        return !first.contains { Double($0) != nil } && Set(first).count == first.count
    }

    /// Field spans of one line (no newline inside), for rainbow-column colouring. Quotes are honoured within the line.
    public static func fieldRanges(in line: NSString, base: Int, delimiter: unichar) -> [NSRange] {
        var out: [NSRange] = []
        var start = 0, quoted = false
        for i in 0..<line.length {
            let c = line.character(at: i)
            if c == 34 { quoted.toggle() }
            else if c == delimiter, !quoted { out.append(NSRange(location: base + start, length: i - start)); start = i + 1 }
        }
        var end = line.length
        while end > start, [10, 13].contains(line.character(at: end - 1)) { end -= 1 }
        out.append(NSRange(location: base + start, length: end - start))
        return out
    }
}

// MARK: JSON lines

public enum JSONLines {
    /// One object per line → columns = top-level keys in first-seen order; nested values as compact JSON;
    /// scalar lines go in a `value` column. Invalid lines are skipped and reported.
    public static func parse(_ text: String) -> DataTable {
        var columns: [String] = []
        var index: [String: Int] = [:]
        var rows: [[String: String?]] = []
        var warnings: [String] = []
        var bad = 0
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let node = try? JSON.parse(t) else {
                bad += 1
                if warnings.count < 5 { warnings.append("Line \(n + 1): invalid JSON") }
                continue
            }
            var row: [String: String?] = [:]
            if case .object = node.value {
                for child in node.children {
                    let k = child.key ?? ""
                    if index[k] == nil { index[k] = columns.count; columns.append(k) }
                    row[k] = cell(child)
                }
            } else {
                if index["value"] == nil { index["value"] = columns.count; columns.append("value") }
                row["value"] = cell(node)
            }
            rows.append(row)
        }
        if bad > warnings.count { warnings.append("… \(bad) invalid lines in total") }
        let grid = rows.map { r in columns.map { r[$0] ?? nil } }
        return DataTable(columns: columns, rows: grid, warnings: warnings)
    }

    static func cell(_ n: Node) -> String? {
        switch n.value {
        case .null: return nil
        case .string(let s): return s
        case .object, .array: return JSON.format(n, indent: 0)
        default: return JSON.format(n, indent: 0)
        }
    }
}
