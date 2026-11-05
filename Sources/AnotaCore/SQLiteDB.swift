import Foundation
import SQLite3

/// Thin wrapper over the system SQLite (no dependency). Opens files read-only unless asked.
public final class SQLiteDB: @unchecked Sendable {  // used from one task at a time
    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let message: String
        /// UTF-8 byte offset of the error in the SQL text, when SQLite reports one.
        public var offset: Int? = nil
        public var description: String { message }
    }

    public struct Object: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable { case table, view }
        public let name: String
        public let kind: Kind
        public var columns: [Column]
        public var indexes: [String] = []
        public var id: String { name }
    }

    public struct Column: Sendable, Equatable {
        public let name: String
        public let type: String
        public let primaryKey: Bool
        public let notNull: Bool
    }

    private var db: OpaquePointer?

    /// `path` nil = a private in-memory database.
    public init(path: String?, readOnly: Bool = true) throws {
        let flags = path == nil || !readOnly ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path ?? ":memory:", &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open"
            sqlite3_close(db)
            throw Failure(message: msg)
        }
        // Untrusted files: don't let a database's own schema (views, triggers, defaults) call functions with side
        // effects, and refuse writes on file databases even if a statement slips through. Extension loading stays
        // off (the C API default; we never enable it).
        try exec("PRAGMA trusted_schema = OFF")
        if path != nil, readOnly { try exec("PRAGMA query_only = ON") }
    }

    deinit { sqlite3_close(db) }

    /// Tables and views (excluding SQLite's internal ones) with their columns.
    public func schema() throws -> [Object] {
        let list = try query("SELECT name, type FROM sqlite_schema WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name")
        return try list.rows.map { r in
            let name = r[0] ?? ""
            let info = try query("SELECT name, type, \"notnull\", pk FROM pragma_table_info(?)", [name])
            let idx = try query("SELECT name FROM pragma_index_list(?)", [name])
            return Object(name: name, kind: r[1] == "view" ? .view : .table, columns: info.rows.map {
                Column(name: $0[0] ?? "", type: $0[1] ?? "", primaryKey: ($0[3] ?? "0") != "0", notNull: $0[2] == "1")
            }, indexes: idx.rows.compactMap { $0[0] })
        }
    }

    /// Run one statement; rows are capped at `limit` (then `truncated`). Values are text; BLOBs summarised.
    public func query(_ sql: String, _ args: [String] = [], limit: Int = 100_000) throws -> DataTable {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error(positioned: true) }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, SQLITE_TRANSIENT) }
        let n = Int(sqlite3_column_count(stmt))
        let columns = (0..<n).map { String(cString: sqlite3_column_name(stmt, Int32($0))) }
        var rows: [[String?]] = []
        var truncated = false
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error() }
            if rows.count == limit { truncated = true; break }
            rows.append((0..<n).map { i -> String? in
                let c = Int32(i)
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_NULL: return nil
                case SQLITE_BLOB: return "<BLOB \(sqlite3_column_bytes(stmt, c)) bytes>"
                default: return String(cString: sqlite3_column_text(stmt, c))
                }
            })
        }
        return DataTable(columns: columns, rows: rows, truncated: truncated)
    }

    /// Copy a table into this (in-memory) database as `name`, all columns TEXT, so files can be queried with SQL.
    public func importTable(_ t: DataTable, as name: String) throws {
        let cols = Self.uniqueNames(t.columns)
        try exec("DROP TABLE IF EXISTS \(Self.quote(name))")
        try exec("CREATE TABLE \(Self.quote(name)) (\(cols.map { Self.quote($0) + " TEXT" }.joined(separator: ", ")))")
        try exec("BEGIN")
        var stmt: OpaquePointer?
        let marks = Array(repeating: "?", count: cols.count).joined(separator: ",")
        guard sqlite3_prepare_v2(db, "INSERT INTO \(Self.quote(name)) VALUES (\(marks))", -1, &stmt, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(stmt) }
        for row in t.rows {
            for i in cols.indices {
                if i < row.count, let v = row[i] { sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT) }
                else { sqlite3_bind_null(stmt, Int32(i + 1)) }
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
            sqlite3_reset(stmt)
        }
        try exec("COMMIT")
    }

    public func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    public static func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// SQL-safe table name from a file name: `sales 2026.csv` → `sales_2026`.
    public static func tableName(for file: String) -> String {
        let base = (file as NSString).deletingPathExtension
        let cleaned = String(base.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return cleaned.first?.isNumber == false ? cleaned : "t_" + cleaned
    }

    static func uniqueNames(_ names: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return names.map { n in
            let k = n.lowercased()
            defer { seen[k, default: 0] += 1 }
            return seen[k].map { "\(n)_\($0 + 1)" } ?? n
        }
    }

    private func error(positioned: Bool = false) -> Failure {
        let off = positioned ? Int(sqlite3_error_offset(db)) : -1
        return Failure(message: String(cString: sqlite3_errmsg(db)), offset: off >= 0 ? off : nil)
    }

    /// Number of rows in a table or view (may be slow on huge views).
    public func count(_ name: String) throws -> Int {
        let cell = try query("SELECT count(*) FROM \(Self.quote(name))").rows.first?.first ?? nil
        return cell.flatMap(Int.init) ?? 0
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
