import Foundation

/// The one tree every structured format (JSON, INI/.env, plist, later YAML/TOML) is turned into.
public struct Node: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case object, array
        case string(String)
        case number(String)  // original text, so formatting round-trips exactly
        case bool(Bool)
        case null
    }

    public var key: String?
    public var value: Value
    public var children: [Node]
    /// Source range of the value (UTF-16 offsets), when the parser knows it.
    public var range: NSRange?

    public init(key: String? = nil, value: Value, children: [Node] = [], range: NSRange? = nil) {
        self.key = key; self.value = value; self.children = children; self.range = range
    }

    public var isContainer: Bool { value == .object || value == .array }
}

public struct ParseError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var line: Int
    public var column: Int
    public var description: String { "Line \(line), column \(column): \(message)" }
    public init(message: String, line: Int, column: Int) { self.message = message; self.line = line; self.column = column }
}

// MARK: Tree items (what the viewer shows)

public struct TreeItem: Identifiable, Sendable, Equatable {
    public let id: String  // path, e.g. $.users[0].name
    public let key: String?
    public let value: Node.Value
    public let range: NSRange?
    public let count: Int
    public var children: [TreeItem]?

    public static func build(_ node: Node, path: String = "$") -> TreeItem {
        TreeItem(
            id: path, key: node.key, value: node.value, range: node.range, count: node.children.count,
            children: node.isContainer
                ? node.children.enumerated().map { i, c in
                    build(c, path: node.value == .array ? "\(path)[\(i)]" : childPath(path, key: c.key ?? ""))
                } : nil)
    }

    static func childPath(_ parent: String, key: String) -> String {
        let simple = !key.isEmpty && key.first!.isLetter
            && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
        return simple ? "\(parent).\(key)" : "\(parent)[\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\"]"
    }

    public var displayValue: String {
        switch value {
        case .object: "{\(count)}"
        case .array: "[\(count)]"
        case .string(let s): "\"\(s)\""
        case .number(let n): n
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        }
    }

    /// Keeps items whose key or value contains `query` (case-insensitive), plus their ancestors.
    public func filtered(_ query: String) -> TreeItem? {
        guard !query.isEmpty else { return self }
        let hit = (key ?? "").localizedCaseInsensitiveContains(query)
            || (!value.isContainer && displayValue.localizedCaseInsensitiveContains(query))
        if hit { return self }
        let kids = children?.compactMap { $0.filtered(query) } ?? []
        guard !kids.isEmpty else { return nil }
        var copy = self
        copy.children = kids
        return copy
    }

    /// Ids of every container in the tree (for "Expand All").
    public var containerIDs: [String] {
        guard let children else { return [] }
        return [id] + children.flatMap(\.containerIDs)
    }
}

extension Node.Value {
    var isContainer: Bool { self == .object || self == .array }
}

// MARK: JSON (order-preserving, tolerant of // and /* */ comments and trailing commas)

public enum JSON {
    public static func parse(_ text: String) throws -> Node {
        var p = JSONParser(Array(text.utf16))
        let node = try p.value(key: nil)
        p.skip()
        if p.i < p.s.count { throw p.error("Unexpected content after the top-level value") }
        return node
    }

    /// Serialize, keeping key order and original number text. `indent: 0` = minified.
    public static func format(_ node: Node, indent: Int = 2) -> String {
        var out = ""
        write(node, into: &out, indent: indent, level: 0)
        return out
    }

    private static func write(_ n: Node, into out: inout String, indent: Int, level: Int) {
        let pad = indent > 0 ? "\n" + String(repeating: " ", count: indent * (level + 1)) : ""
        let close = indent > 0 ? "\n" + String(repeating: " ", count: indent * level) : ""
        switch n.value {
        case .object, .array:
            let isObject = n.value == .object
            out += isObject ? "{" : "["
            guard !n.children.isEmpty else { out += isObject ? "}" : "]"; return }
            for (i, c) in n.children.enumerated() {
                out += (i > 0 ? "," : "") + pad
                if isObject { out += quote(c.key ?? "") + (indent > 0 ? ": " : ":") }
                write(c, into: &out, indent: indent, level: level + 1)
            }
            out += close + (isObject ? "}" : "]")
        case .string(let s): out += quote(s)
        case .number(let s): out += s
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    public static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }
}

private struct JSONParser {
    let s: [UInt16]
    var i = 0
    init(_ s: [UInt16]) { self.s = s }

    private static func c(_ ch: Unicode.Scalar) -> UInt16 { UInt16(ch.value) }
    private var peek: UInt16? { i < s.count ? s[i] : nil }

    func error(_ message: String) -> ParseError {
        var line = 1, col = 1
        for u in s[0..<min(i, s.count)] {
            if u == 10 { line += 1; col = 1 } else { col += 1 }
        }
        return ParseError(message: message, line: line, column: col)
    }

    mutating func skip() {
        while let ch = peek {
            if ch == 32 || ch == 9 || ch == 10 || ch == 13 { i += 1 }
            else if ch == Self.c("/"), i + 1 < s.count, s[i + 1] == Self.c("/") {
                while let x = peek, x != 10 { i += 1 }
            } else if ch == Self.c("/"), i + 1 < s.count, s[i + 1] == Self.c("*") {
                i += 2
                while i + 1 < s.count, !(s[i] == Self.c("*") && s[i + 1] == Self.c("/")) { i += 1 }
                i = min(i + 2, s.count)
            } else { return }
        }
    }

    private mutating func expect(_ ch: Unicode.Scalar) throws {
        skip()
        guard peek == Self.c(ch) else { throw error("Expected “\(ch)”") }
        i += 1
    }

    mutating func value(key: String?) throws -> Node {
        skip()
        guard let ch = peek else { throw error("Unexpected end of input") }
        let start = i
        func node(_ v: Node.Value, _ kids: [Node] = []) -> Node {
            Node(key: key, value: v, children: kids, range: NSRange(location: start, length: i - start))
        }
        switch ch {
        case Self.c("{"), Self.c("["):
            let isObject = ch == Self.c("{")
            let end = Self.c(isObject ? "}" : "]")
            i += 1
            var kids: [Node] = []
            skip()
            while peek != end {
                if isObject {
                    skip()
                    guard peek == Self.c("\"") else { throw error("Expected a quoted key") }
                    let k = try string()
                    try expect(":")
                    kids.append(try value(key: k))
                } else {
                    kids.append(try value(key: nil))
                }
                skip()
                if peek == Self.c(",") { i += 1; skip() }  // a trailing comma is tolerated
                else if peek != end { throw error("Expected “,” or “\(isObject ? "}" : "]")”") }
            }
            i += 1
            return node(isObject ? .object : .array, kids)
        case Self.c("\""):
            return node(.string(try string()))
        case Self.c("t"), Self.c("f"), Self.c("n"):
            for (word, v) in [("true", Node.Value.bool(true)), ("false", .bool(false)), ("null", .null)]
            where s[i...].starts(with: word.utf16) {
                i += word.utf16.count
                return node(v)
            }
            throw error("Unexpected token")
        default:
            let allowed = Set("+-0123456789.eE".utf16)
            while let x = peek, allowed.contains(x) { i += 1 }
            guard i > start else { throw error("Unexpected character") }
            let text = String(decoding: s[start..<i], as: UTF16.self)
            guard Double(text) != nil else { i = start; throw error("Invalid number “\(text)”") }
            return node(.number(text))
        }
    }

    private mutating func string() throws -> String {
        i += 1  // opening quote
        var out: [UInt16] = []
        while true {
            guard let ch = peek, ch != 10 else { throw error("Unterminated string") }
            i += 1
            if ch == Self.c("\"") { return String(decoding: out, as: UTF16.self) }
            guard ch == Self.c("\\") else { out.append(ch); continue }
            guard let e = peek else { throw error("Unterminated string") }
            i += 1
            switch e {
            case Self.c("n"): out.append(10)
            case Self.c("t"): out.append(9)
            case Self.c("r"): out.append(13)
            case Self.c("b"): out.append(8)
            case Self.c("f"): out.append(12)
            case Self.c("u"):
                guard i + 4 <= s.count, let v = UInt16(String(decoding: s[i..<i + 4], as: UTF16.self), radix: 16)
                else { throw error("Invalid \\u escape") }
                out.append(v)
                i += 4
            default: out.append(e)  // \" \\ \/
            }
        }
    }
}

// MARK: INI / .env / .properties

public enum INI {
    /// `[section]` → object; `key = value`, `key: value`, `export KEY=value`; `;` and `#` comments.
    public static func parse(_ text: String) -> Node {
        var root = Node(value: .object)
        var section: Int?  // index into root.children
        var offset = 0
        for line in text.components(separatedBy: "\n") {
            defer { offset += (line as NSString).length + 1 }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix(";") || t.hasPrefix("#") { continue }
            if t.hasPrefix("["), t.hasSuffix("]") {
                root.children.append(Node(key: String(t.dropFirst().dropLast()), value: .object))
                section = root.children.count - 1
                continue
            }
            var body = Substring(t)
            if body.hasPrefix("export ") { body = body.dropFirst(7) }
            guard let sep = body.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = body[..<sep].trimmingCharacters(in: .whitespaces)
            var value = body[body.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f {
                value = String(value.dropFirst().dropLast())
            }
            let node = Node(key: key, value: .string(value),
                            range: NSRange(location: offset, length: (line as NSString).length))
            if let section { root.children[section].children.append(node) } else { root.children.append(node) }
        }
        return root
    }
}

// MARK: Property lists (XML)

public enum Plist {
    public static func parse(_ text: String) throws -> Node {
        do {
            let obj = try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil)
            return node(obj, key: nil)
        } catch {
            throw ParseError(message: "Not a valid property list", line: 1, column: 1)
        }
    }

    private static func node(_ obj: Any, key: String?) -> Node {
        switch obj {
        case let d as [String: Any]:
            // plist dictionaries are unordered; sort keys for a stable view.
            return Node(key: key, value: .object, children: d.keys.sorted().map { node(d[$0]!, key: $0) })
        case let a as [Any]:
            return Node(key: key, value: .array, children: a.map { node($0, key: nil) })
        case let s as String: return Node(key: key, value: .string(s))
        case let b as Bool where type(of: obj) == type(of: NSNumber(value: true)): return Node(key: key, value: .bool(b))
        case let n as NSNumber: return Node(key: key, value: .number(n.stringValue))
        case let d as Date: return Node(key: key, value: .string(ISO8601DateFormatter().string(from: d)))
        case let d as Data: return Node(key: key, value: .string("<\(d.count) bytes>"))
        default: return Node(key: key, value: .string("\(obj)"))
        }
    }
}
