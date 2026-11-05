import Compression
import Foundation

/// Read-only `.xlsx` reader: the file is a ZIP of XML parts. Cached formula values are shown (no recalculation);
/// date-formatted numbers become `yyyy-MM-dd[ HH:mm:ss]`.
public enum XLSX {
    public struct Sheet: Sendable, Equatable {
        public let name: String
        public let table: DataTable
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Most cells one sheet may produce (rows × columns).
    static let maxCells = 20_000_000

    public static func read(_ url: URL, rowLimit: Int = 200_000) throws -> [Sheet] {
        let zip = try Zip(Data(contentsOf: url))
        let shared = try zip.file("xl/sharedStrings.xml").map(SharedStrings.parse) ?? []
        let dateStyles = try zip.file("xl/styles.xml").map(Styles.dateStyleIndexes) ?? []
        guard let workbook = try zip.file("xl/workbook.xml") else { throw Failure(message: "Not an Excel workbook") }
        let rels = try zip.file("xl/_rels/workbook.xml.rels").map(Relationships.parse) ?? [:]
        return try Workbook.sheets(workbook).compactMap { name, rid in
            guard let target = rels[rid] else { return nil }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let xml = try zip.file(path) else { return nil }
            return Sheet(name: name, table: SheetParser.parse(xml, shared: shared, dateStyles: dateStyles, rowLimit: rowLimit))
        }
    }

    // MARK: ZIP (stored + deflate entries via the central directory)

    struct Zip {
        let data: Data
        var entries: [String: (offset: Int, method: UInt16, compressed: Int, size: Int)] = [:]

        init(_ data: Data) throws {
            self.data = data
            let bytes = [UInt8](data)
            func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
            func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
            // End of central directory: signature 0x06054b50, searched from the end (comment ≤ 64K).
            var eocd = -1
            var i = bytes.count - 22
            while i >= max(0, bytes.count - 22 - 65_535) {
                if u32(i) == 0x0605_4b50 { eocd = i; break }
                i -= 1
            }
            guard eocd >= 0 else { throw Failure(message: "Not a ZIP file (corrupt or not .xlsx)") }
            var p = u32(eocd + 16)
            for _ in 0..<u16(eocd + 10) {
                // Every offset comes from the file: check it before reading (malformed files must throw, not crash).
                guard p + 46 <= bytes.count, u32(p) == 0x0201_4b50 else { throw Failure(message: "Corrupt ZIP directory") }
                let nameLen = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32)
                guard p + 46 + nameLen + extra + comment <= bytes.count else { throw Failure(message: "Corrupt ZIP directory") }
                let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
                entries[name] = (u32(p + 42), UInt16(u16(p + 10)), u32(p + 20), u32(p + 24))
                p += 46 + nameLen + extra + comment
            }
        }

        func file(_ name: String) throws -> Data? {
            guard let e = entries[name] else { return nil }
            let bytes = data
            func u16(_ i: Int) -> Int { Int(bytes[bytes.startIndex + i]) | Int(bytes[bytes.startIndex + i + 1]) << 8 }
            guard e.offset >= 0, e.offset + 30 <= bytes.count else { throw Failure(message: "Corrupt ZIP entry \(name)") }
            let start = e.offset + 30 + u16(e.offset + 26) + u16(e.offset + 28)  // skip the local header
            guard e.compressed >= 0, start + e.compressed <= bytes.count else { throw Failure(message: "Corrupt ZIP entry \(name)") }
            let raw = bytes.subdata(in: start..<(start + e.compressed))
            switch e.method {
            case 0: return raw
            case 8: return try inflate(raw, size: e.size)
            default: throw Failure(message: "Unsupported ZIP compression \(e.method)")
            }
        }

        /// Raw DEFLATE (Apple's COMPRESSION_ZLIB is headerless RFC 1951, which is what ZIP stores).
        /// Largest part we'll inflate, and the most DEFLATE can expand (its hard limit is ~1032:1).
        static let maxPartSize = 512 << 20, maxRatio = 1_100

        private func inflate(_ raw: Data, size: Int) throws -> Data {
            guard size > 0 else { return Data() }
            // The size is declared by the file: refuse absurd ones before allocating (decompression bombs).
            guard size <= Self.maxPartSize, size <= max(raw.count, 1) * Self.maxRatio else {
                throw Failure(message: "Workbook part is too large to open")
            }
            var out = Data(count: size)
            let n = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard n == size else { throw Failure(message: "Can't decompress workbook part") }
            return out
        }
    }

    // MARK: XML parts

    /// Collects attributes / text for simple SAX handlers.
    class Handler: NSObject, XMLParserDelegate {
        static func run(_ data: Data, _ h: Handler) { let p = XMLParser(data: data); p.delegate = h; p.parse() }
    }

    enum SharedStrings {
        static func parse(_ data: Data) -> [String] {
            final class H: Handler {
                var out: [String] = [], cur = "", inT = false, inRPh = false
                func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
                    if e == "si" { cur = "" } else if e == "t" { inT = true } else if e == "rPh" { inRPh = true }
                }
                func parser(_ p: XMLParser, foundCharacters s: String) { if inT && !inRPh { cur += s } }
                func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                    if e == "t" { inT = false } else if e == "rPh" { inRPh = false } else if e == "si" { out.append(cur) }
                }
            }
            let h = H(); Handler.run(data, h); return h.out
        }
    }

    enum Workbook {
        static func sheets(_ data: Data) -> [(String, String)] {
            final class H: Handler {
                var out: [(String, String)] = []
                func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                    if e == "sheet", let n = a["name"], let id = a["r:id"] ?? a.first(where: { $0.key.hasSuffix(":id") })?.value { out.append((n, id)) }
                }
            }
            let h = H(); Handler.run(data, h); return h.out
        }
    }

    enum Relationships {
        static func parse(_ data: Data) -> [String: String] {
            final class H: Handler {
                var out: [String: String] = [:]
                func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                    if e == "Relationship", let id = a["Id"], let t = a["Target"] { out[id] = t }
                }
            }
            let h = H(); Handler.run(data, h); return h.out
        }
    }

    enum Styles {
        /// Indexes into `cellXfs` whose number format is a date/time.
        static func dateStyleIndexes(_ data: Data) -> Set<Int> {
            final class H: Handler {
                var custom: [Int: String] = [:], xfs: [Int] = [], inXfs = false
                func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                    if e == "numFmt", let id = a["numFmtId"].flatMap(Int.init), let code = a["formatCode"] { custom[id] = code }
                    if e == "cellXfs" { inXfs = true }
                    if e == "xf", inXfs { xfs.append(a["numFmtId"].flatMap(Int.init) ?? 0) }
                }
                func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { if e == "cellXfs" { inXfs = false } }
            }
            let h = H(); Handler.run(data, h)
            func isDate(_ id: Int) -> Bool {
                if (14...22).contains(id) || (45...47).contains(id) { return true }
                guard let code = h.custom[id] else { return false }
                let stripped = code.replacingOccurrences(of: #"\[[^\]]*\]|"[^"]*""#, with: "", options: .regularExpression).lowercased()
                return stripped.contains("y") || stripped.contains("d") || (stripped.contains("h") && stripped.contains("m"))
            }
            return Set(h.xfs.enumerated().filter { isDate($0.element) }.map(\.offset))
        }
    }

    enum SheetParser {
        static func parse(_ data: Data, shared: [String], dateStyles: Set<Int>, rowLimit: Int) -> DataTable {
            final class H: Handler {
                let shared: [String], dateStyles: Set<Int>, rowLimit: Int
                var rows: [[Int: String]] = [], row: [Int: String] = [:], width = 0, truncated = false
                var col = 0, type = "", style = 0, text = "", inValue = false
                init(_ s: [String], _ d: Set<Int>, _ l: Int) { shared = s; dateStyles = d; rowLimit = l }
                func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                    switch e {
                    case "row": row = [:]
                    case "c":
                        col = a["r"].flatMap(XLSX.column) ?? min(row.keys.max().map { $0 + 1 } ?? 0, XLSX.maxColumns - 1)
                        type = a["t"] ?? "n"; style = a["s"].flatMap(Int.init) ?? 0; text = ""
                    case "v", "t": inValue = true
                    default: break
                    }
                }
                func parser(_ p: XMLParser, foundCharacters s: String) { if inValue { text += s } }
                func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                    switch e {
                    case "v", "t": inValue = false
                    case "c":
                        var v: String? = text
                        switch type {
                        case "s": v = Int(text).flatMap { $0 < shared.count ? shared[$0] : nil }
                        case "b": v = text == "1" ? "TRUE" : "FALSE"
                        case "e", "str", "inlineStr": break
                        default:
                            if text.isEmpty { v = nil }
                            else if dateStyles.contains(style), let d = Double(text) { v = XLSX.date(d) }
                        }
                        if let v { row[col] = v; width = max(width, col + 1) }
                    case "row":
                        // Cap rows and total cells (rows × width), so a sheet with a cell at XFD1048576 can't
                        // make us build a billions-of-cells grid.
                        if rows.count >= rowLimit || rows.count * max(width, 1) >= XLSX.maxCells {
                            truncated = true; p.abortParsing(); return
                        }
                        rows.append(row)
                    default: break
                    }
                }
            }
            let h = H(shared, dateStyles, rowLimit)
            Handler.run(data, h)
            var grid = h.rows.map { r in (0..<h.width).map { r[$0] } }
            // First row is the header when it's all text (the usual layout); else generic letters.
            let header: [String]
            if let first = grid.first, !first.isEmpty, first.allSatisfy({ $0 != nil && Double($0!) == nil }) {
                header = first.map { $0! }
                grid.removeFirst()
            } else {
                header = (0..<h.width).map(XLSX.letters)
            }
            return DataTable(columns: header, rows: grid, truncated: h.truncated,
                             hasHeaderRow: header.count == h.width && h.width > 0 && grid.count < h.rows.count, letterNames: true)
        }
    }

    /// Excel's limit: 16,384 columns (A…XFD).
    static let maxColumns = 16_384

    /// "C12" → 2 (0-based column); nil for anything outside A…XFD or not a column reference.
    static func column(_ ref: String) -> Int? {
        var n = 0
        for u in ref.prefix(while: { $0.isASCII && $0.isLetter }).uppercased().unicodeScalars {
            n = n * 26 + Int(u.value) - 64
            if n > maxColumns { return nil }  // also stops overflow on absurd references
        }
        return n > 0 ? n - 1 : nil
    }

    /// 0 → "A", 26 → "AA".
    static func letters(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }

    /// Excel serial date (1900 system) → ISO text.
    static func date(_ serial: Double) -> String {
        let base = Date(timeIntervalSince1970: -2_209_161_600)  // 1899-12-30, absorbs the 1900 leap-year bug
        let d = base.addingTimeInterval((serial * 86_400).rounded())
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = serial.truncatingRemainder(dividingBy: 1) == 0 ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}
