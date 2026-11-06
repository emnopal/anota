import Foundation

/// LSP Content-Length is a UTF-8 byte count, not a character count.
public enum LSPFraming {
    public static func frame(_ body: Data) -> Data { Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body }
    public static func take(from buffer: inout Data) throws -> Data? {
        guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 8192 { throw Failure.invalidHeader }
            return nil
        }
        let header = String(decoding: buffer[..<boundary.lowerBound], as: UTF8.self)
        guard let line = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
              let size = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)), size >= 0, size <= 32_000_000 else { throw Failure.invalidHeader }
        let start = boundary.upperBound
        guard buffer.count - start >= size else { return nil }
        let body = Data(buffer[start..<(start + size)])
        buffer.removeSubrange(..<(start + size))
        return body
    }
    public enum Failure: Error { case invalidHeader }
}
