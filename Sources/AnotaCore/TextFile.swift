import Foundation
import CryptoKit

public enum LineEnding: String, Codable, Sendable, CaseIterable {
    case lf = "\n", crlf = "\r\n", cr = "\r"
    public var label: String {
        switch self { case .lf: "LF"; case .crlf: "CRLF"; case .cr: "CR" }
    }
}

/// A decoded text file. `text` always uses "\n"; the original line ending is kept
/// separately and restored on encode.
public struct TextFile: Sendable, Equatable {
    public enum Failure: Error, Equatable, LocalizedError {
        case changedOnDisk
        case binary
        case unrepresentable  // text has characters the chosen encoding can't hold
        public var errorDescription: String? {
            switch self {
            case .changedOnDisk: "The file changed on disk during saving. Review the external version and try again."
            case .binary: "This file contains binary data."
            case .unrepresentable: "The text cannot be saved in the selected encoding."
            }
        }
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

    /// Coordinate replacement and recheck the version after gaining access to the file.
    public func write(to url: URL, matching expected: FileRevision) throws {
        let data = try encoded()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            result = Result {
                guard try FileRevision.read(target) == expected else { throw Failure.changedOnDisk }
                try data.write(to: target, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }
}

public func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}


public enum FileRevision: Equatable, Sendable {
    case missing
    case contents(Data)

    public init(contents: Data) { self = .contents(Data(SHA256.hash(data: contents))) }

    public static func read(_ url: URL) throws -> Self {
        do { return Self(contents: try Data(contentsOf: url)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .missing }
    }
}
