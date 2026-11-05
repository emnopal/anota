import Foundation

public enum LineEnding: String, Codable, Sendable, CaseIterable {
    case lf = "\n", crlf = "\r\n", cr = "\r"
    public var label: String {
        switch self { case .lf: "LF"; case .crlf: "CRLF"; case .cr: "CR" }
    }
}

/// A decoded text file. `text` always uses "\n"; the original line ending is kept
/// separately and restored on encode.
public struct TextFile: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case binary
        case unrepresentable  // text has characters the chosen encoding can't hold
    }

    public var text: String
    public var encoding: String.Encoding
    public var lineEnding: LineEnding

    public init(text: String, encoding: String.Encoding = .utf8, lineEnding: LineEnding = .lf) {
        self.text = text
        self.encoding = encoding
        self.lineEnding = lineEnding
    }

    public static func read(_ url: URL) throws -> TextFile {
        try decode(Data(contentsOf: url))
    }

    // ponytail: a UTF-8 BOM is dropped on read and not rewritten on save.
    public static func decode(_ data: Data) throws -> TextFile {
        var body = data
        let encoding: String.Encoding
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            encoding = .utf8
            body = data.dropFirst(3)
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16
        } else {
            if data.prefix(8000).contains(0) { throw Failure.binary }
            encoding = String(data: data, encoding: .utf8) != nil ? .utf8 : .isoLatin1
        }
        guard let raw = String(data: Data(body), encoding: encoding) else { throw Failure.binary }
        let ns = raw as NSString
        let lineEnding: LineEnding =
            ns.range(of: "\r\n").location != NSNotFound ? .crlf :
            ns.range(of: "\r").location != NSNotFound ? .cr : .lf
        let text = lineEnding == .lf ? raw :
            raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return TextFile(text: text, encoding: encoding, lineEnding: lineEnding)
    }

    public func encoded() throws -> Data {
        let out = lineEnding == .lf ? text : text.replacingOccurrences(of: "\n", with: lineEnding.rawValue)
        guard let data = out.data(using: encoding, allowLossyConversion: false) else { throw Failure.unrepresentable }
        return data
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }
}

public func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

/// 1-based line number of the UTF-16 offset `location`.
public func lineNumber(in text: NSString, at location: Int) -> Int {
    (text as String).utf16.prefix(location).reduce(1) { $1 == 10 ? $0 + 1 : $0 }
}
