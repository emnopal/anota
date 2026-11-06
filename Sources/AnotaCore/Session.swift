import Foundation

/// Everything needed to rebuild the window after quit/crash ("hot exit").
public struct Session: Codable, Sendable, Equatable {
    public struct Tab: Codable, Sendable, Equatable {
        public var id: UUID
        public var path: String?
        public var dirty: Bool
        public var encoding: UInt
        public var lineEnding: LineEnding
        public var language: Language
        public var selection: Int
        public var diskDate: Date?

        public init(id: UUID, path: String?, dirty: Bool, encoding: UInt, lineEnding: LineEnding,
                    language: Language, selection: Int, diskDate: Date?) {
            self.id = id; self.path = path; self.dirty = dirty; self.encoding = encoding
            self.lineEnding = lineEnding; self.language = language; self.selection = selection; self.diskDate = diskDate
        }
    }

    public struct Group: Codable, Sendable, Equatable {
        public var id: UUID?
        public var tabs: [UUID]
        public var active: UUID?
        public init(tabs: [UUID], active: UUID?, id: UUID? = nil) { self.tabs = tabs; self.active = active; self.id = id }
    }

    public var tabs: [Tab]
    public var groups: [Group]
    public var layout: PaneLayout?
    public var focused: Int
    public var root: String?
    public var verticalTabs: Bool
    public var wrap: Bool

    public init(tabs: [Tab], groups: [Group], focused: Int, root: String?, verticalTabs: Bool, wrap: Bool, layout: PaneLayout? = nil) {
        self.layout = layout
        self.tabs = tabs; self.groups = groups; self.focused = focused
        self.root = root; self.verticalTabs = verticalTabs; self.wrap = wrap
    }
}

/// Layout: `<dir>/session.json` + `<dir>/buffers/<tab id>.txt` for each dirty tab's content.
public struct SessionStore: Sendable {
    public let dir: URL
    public init(dir: URL) { self.dir = dir }

    public static var standard: SessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SessionStore(dir: base.appending(path: "Anota/Session", directoryHint: .isDirectory))
    }

    private var buffersDir: URL { dir.appending(path: "buffers", directoryHint: .isDirectory) }
    private func bufferURL(_ id: UUID) -> URL { buffersDir.appending(path: "\(id.uuidString).txt") }

    /// `changed`: contents of dirty tabs edited since the last save. Dirty tabs not in
    /// `changed` keep their previously written file. Files of non-dirty tabs are removed.
    /// Buffer files are written before session.json so a crash mid-save never points at missing data.
    public func save(_ session: Session, changed: [UUID: String]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: buffersDir, withIntermediateDirectories: true)
        for (id, text) in changed {
            try Data(text.utf8).write(to: bufferURL(id), options: .atomic)
        }
        try JSONEncoder().encode(session).write(to: dir.appending(path: "session.json"), options: .atomic)
        let keep = Set(session.tabs.filter(\.dirty).map(\.id.uuidString))
        for file in (try? fm.contentsOfDirectory(at: buffersDir, includingPropertiesForKeys: nil)) ?? []
        where !keep.contains(file.deletingPathExtension().lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    public func load() -> (session: Session, texts: [UUID: String])? {
        guard let data = try? Data(contentsOf: dir.appending(path: "session.json")),
              let session = try? JSONDecoder().decode(Session.self, from: data) else { return nil }
        var texts: [UUID: String] = [:]
        for tab in session.tabs where tab.dirty {
            if let d = try? Data(contentsOf: bufferURL(tab.id)) { texts[tab.id] = String(decoding: d, as: UTF8.self) }
        }
        return (session, texts)
    }
}
