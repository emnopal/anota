import CoreServices
import Foundation

/// FSEvents coalesces recursive directory changes, including atomic replacements.
public final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    let changed: @Sendable () -> Void
    public init(paths: [String], changed: @escaping @Sendable () -> Void) {
        self.changed = changed
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().changed()
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .global(qos: .utility))
            FSEventStreamStart(stream)
        }
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
