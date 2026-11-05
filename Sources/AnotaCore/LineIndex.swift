import Foundation

/// UTF-16 offsets of every line start, for O(log n) offset → line lookups on big files.
/// Building it is one linear scan of the raw UTF-16 buffer (fast even for 10 MB+).
public struct LineIndex: Sendable {
    /// `starts[i]` is the offset where line `i + 1` begins; `starts[0] == 0`.
    public private(set) var starts: [Int] = [0]
    public let length: Int

    public init(_ text: NSString) {
        length = text.length
        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: chunk)
        var loc = 0
        while loc < length {
            let n = min(chunk, length - loc)
            buf.withUnsafeMutableBufferPointer { p in
                text.getCharacters(p.baseAddress!, range: NSRange(location: loc, length: n))
                for i in 0..<n where p[i] == 10 { starts.append(loc + i + 1) }
            }
            loc += n
        }
    }

    public var lineCount: Int { starts.count }

    /// 1-based line containing `offset` (clamped to the text).
    public func line(at offset: Int) -> Int {
        let o = min(max(offset, 0), length)
        var lo = 0, hi = starts.count - 1  // last start <= o
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// Offset where 1-based `line` starts (clamped).
    public func start(ofLine line: Int) -> Int { starts[min(max(line, 1), starts.count) - 1] }
}

public func lineNumber(in text: NSString, at location: Int) -> Int {
    LineIndex(text).line(at: location)
}
