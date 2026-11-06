import AppKit
import AnotaCore
import Observation

/// One open document. The NSTextStorage is shared by every editor view showing it
/// (split view = several layout managers on one storage).
@Observable
final class Buffer: NSObject, Identifiable {
    let id: UUID
    var url: URL? {
        didSet { if url != oldValue { language = Language.detect(url) } }
    }
    var language: Language {
        didSet {
            highlighter = Highlighter(language)
            highlightAll()
            if !modes.contains(viewMode) { viewMode = modes[0] }
        }
    }
    var encoding: String.Encoding = .utf8
    var lineEnding: LineEnding = .lf
    var isDirty = false
    var conflict = false  // file changed on disk while we have unsaved edits
    var caretLine = 1
    var caretColumn = 1
    var revision = 0          // bumps on every text change (observed by tree/preview views)
    var viewMode: ViewMode = .text
    var reveal: NSRange?      // set to select + scroll to a range in the editor

    @ObservationIgnored var selection = NSRange(location: 0, length: 0)
    @ObservationIgnored var diskRevision: FileRevision?
    @ObservationIgnored var diskDate: Date?
    @ObservationIgnored let storage = NSTextStorage()
    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored var onEdit: ((Buffer) -> Void)?
    /// ⌘↩ in this buffer's editor runs this instead of "Insert Line Below" (the data viewer's SQL box).
    @ObservationIgnored var onCommandReturn: (() -> Void)?
    @ObservationIgnored private var highlighter: Highlighter
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var lineCache: LineIndex?
    @ObservationIgnored private var restyleQueue: [NSRange] = []  // ranges still to colour, most urgent first
    @ObservationIgnored private var restyleScheduled = false
    @ObservationIgnored private var restyleWork: DispatchWorkItem?
    @ObservationIgnored private var parsingInBackground = false
    @ObservationIgnored private var editedDuringParse = false
    /// Above this size a tree-sitter re-parse costs ~100 ms, so it waits for a pause in typing.
    private static let bigText = 300_000

    /// Line-start index of the current text, rebuilt lazily after edits.
    var lines: LineIndex {
        if let l = lineCache, l.length == storage.length { return l }
        let l = LineIndex(storage.string as NSString)
        lineCache = l
        return l
    }

    enum ViewMode: String, CaseIterable { case text, tree, preview, split, grid }

    var name: String { url?.lastPathComponent ?? "Untitled" }

    var isPlist: Bool { url?.pathExtension.lowercased() == "plist" }

    var modes: [ViewMode] {
        if language.isBinaryData { return [.grid] }
        if language.isTabular { return [.grid, .text] }
        if language == .markdown { return [.text, .split, .preview] }
        if [.json, .yaml, .toml, .ini, .dotenv].contains(language) || isPlist { return [.text, .tree] }
        return [.text]
    }

    func parseTree() throws -> Node {
        if isPlist { return try Plist.parse(text) }
        switch language {
        case .ini, .dotenv: return INI.parse(text)
        case .yaml: return try YAML.parse(text)
        case .toml: return try TOML.parse(text)
        default: return try JSON.parse(text)
        }
    }

    /// Undoable programmatic edit (tree edits, replace-all, format).
    func replace(_ range: NSRange, with string: String) {
        let old = storage.attributedSubstring(from: range).string
        storage.replaceCharacters(in: range, with: string)
        let newRange = NSRange(location: range.location, length: (string as NSString).length)
        undoManager.registerUndo(withTarget: self) { $0.replace(newRange, with: old) }
    }

    /// Whole-document rewrite (format, replace all) applied as the smallest edit, so untouched
    /// text keeps its cursor/scroll position and undo restores exactly.
    func replaceAll(with string: String) {
        guard let e = minimalEdit(from: text, to: string) else { return }
        replace(e.range, with: e.replacement)
    }
    var text: String { storage.string }

    init(id: UUID = UUID(), url: URL?, text: String = "") {
        self.id = id
        self.url = url
        let lang = Language.detect(url)
        self.language = lang
        self.highlighter = Highlighter(lang)
        super.init()
        viewMode = modes[0]  // data files open in the grid
        storage.delegate = self
        setText(text)
    }

    static func load(_ url: URL, id: UUID = UUID()) throws -> Buffer {
        var lang = Language.detect(url)
        if lang == .sqlite, !Self.hasSQLiteHeader(url) { lang = .plain }  // a ".db" that isn't SQLite: open as text
        if lang.isBinaryData {
            // SQLite / Excel: no text; the grid reads the file itself (revision bumps when it changes on disk).
            let b = Buffer(id: id, url: url)
            b.diskDate = modificationDate(url)
            b.diskRevision = try? FileRevision.read(url)
            return b
        }
        let data = try Data(contentsOf: url)
        let file = try TextFile.decode(data)
        let b = Buffer(id: id, url: url, text: file.text)
        if b.language != lang { b.language = lang }
        b.encoding = file.encoding
        b.lineEnding = file.lineEnding
        b.diskDate = modificationDate(url)
        b.diskRevision = FileRevision(contents: data)
        return b
    }

    func setText(_ text: String) {
        loading = true
        storage.setAttributedString(NSAttributedString(string: text, attributes: Theme.baseAttributes))
        loading = false
        undoManager.removeAllActions()
    }

    func write(to url: URL, matching expected: FileRevision) throws {
        precondition(!language.isBinaryData, "binary data files are never written as text")
        try TextFile(text: text, encoding: encoding, lineEnding: lineEnding).write(to: url, matching: expected)
        self.url = url
        isDirty = false
        conflict = false
        diskDate = modificationDate(url)
        diskRevision = try FileRevision(contents: TextFile(text: text, encoding: encoding, lineEnding: lineEnding).encoded())
    }

    private static func hasSQLiteHeader(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: 16)) == Data("SQLite format 3\0".utf8)
    }

    func reload() throws {
        guard let url else { return }
        if language.isBinaryData { diskDate = modificationDate(url); revision += 1; return }
        let data = try Data(contentsOf: url)
        let file = try TextFile.decode(data)
        setText(file.text)
        encoding = file.encoding
        lineEnding = file.lineEnding
        isDirty = false
        conflict = false
        diskDate = modificationDate(url)
        diskRevision = FileRevision(contents: data)
    }

    func markEdited() {
        isDirty = true
        onEdit?(self)
    }

    // MARK: Highlighting
    // Colours are layout-manager *temporary* attributes, not text-storage attributes: changing them only
    // redraws, never re-lays-out text, which is what kept long files slow. Work is queued and done in
    // ~100K-character slices per run-loop turn, so opening or editing a huge file never blocks typing.

    /// Recolour everything (language change, a new editor view on this buffer).
    func highlightAll() {
        restyleQueue = [NSRange(location: 0, length: storage.length)]
        if highlighter.usesTreeSitter, storage.length > Self.bigText, !parsingInBackground {
            // First parse of a big file (~1 s per 5 MB) runs off the main thread; edits meanwhile are
            // noted and force a fresh parse afterwards.
            parsingInBackground = true
            editedDuringParse = false
            let h = highlighter
            // A real copy (storage.string is a live view of the mutable text). Immutable, so sharing is safe.
            nonisolated(unsafe) let snapshot = storage.mutableString.copy() as! NSString
            Task {
                _ = await Task.detached { h.update(snapshot) }.value
                parsingInBackground = false
                if editedDuringParse || h !== highlighter { highlighter.reset() }
                scheduleRestyle()
            }
            return
        }
        // Normal-sized files: colour now, before the first frame, so a newly opened file never flashes uncoloured.
        if storage.length <= Self.bigText, !parsingInBackground { drainRestyle(); return }
        scheduleRestyle()
    }

    private func scheduleRestyle(after delay: TimeInterval = 0) {
        if delay > 0 {
            // Debounce: re-arm on every keystroke, run once typing pauses.
            restyleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.drainRestyle() }
            restyleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return
        }
        guard !restyleScheduled else { return }
        restyleScheduled = true
        DispatchQueue.main.async { [weak self] in self?.drainRestyle() }
    }

    private func drainRestyle() {
        restyleScheduled = false
        guard !parsingInBackground else { return }  // resumes when the background parse lands
        let text = storage.string as NSString
        let length = text.length
        restyleQueue.append(contentsOf: highlighter.update(text))
        var budget = 100_000
        while budget > 0, !restyleQueue.isEmpty {
            let r = NSIntersectionRange(restyleQueue.removeFirst(), NSRange(location: 0, length: length))
            guard r.length > 0 || length == 0 else { continue }
            var slice = r
            if r.length > budget {
                // Cut at a line end, put the rest back at the front.
                let cut = NSMaxRange(text.lineRange(for: NSRange(location: r.location + budget, length: 0)))
                slice = NSRange(location: r.location, length: min(cut, NSMaxRange(r)) - r.location)
                if NSMaxRange(slice) < NSMaxRange(r) {
                    restyleQueue.insert(NSRange(location: NSMaxRange(slice), length: NSMaxRange(r) - NSMaxRange(slice)), at: 0)
                }
            }
            applyHighlight(slice, text)
            budget -= max(slice.length, 1)
        }
        if !restyleQueue.isEmpty { scheduleRestyle() }
    }

    private func applyHighlight(_ range: NSRange, _ text: NSString) {
        let tokens = highlighter.tokens(in: text, range: range)
        for lm in storage.layoutManagers {
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            for t in tokens {
                lm.addTemporaryAttribute(.foregroundColor, value: Theme.color(t.token), forCharacterRange: t.range)
            }
        }
    }

    /// Text changed: tell the parser, shift queued work, and queue the edited lines first.
    fileprivate func noteEdit(_ edited: NSRange, delta: Int) {
        lineCache = nil
        if parsingInBackground {
            editedDuringParse = true
        } else if highlighter.usesTreeSitter {
            highlighter.edited(edited, changeInLength: delta, lines: lines)
        }
        let oldEnd = NSMaxRange(edited) - delta
        restyleQueue = restyleQueue.map { r in
            r.location >= oldEnd ? NSRange(location: max(r.location + delta, 0), length: r.length) : r
        }
        let ns = storage.string as NSString
        restyleQueue.insert(ns.lineRange(for: NSRange(location: edited.location, length: min(edited.length, ns.length - edited.location))), at: 0)
        scheduleRestyle(after: highlighter.usesTreeSitter && ns.length > Self.bigText ? 0.25 : 0)
    }
}

extension Buffer: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        noteEdit(editedRange, delta: delta)
        revision += 1
        if !loading { markEdited() }
    }
}

@Observable
final class EditorGroup: Identifiable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
    var tabs: [Buffer] = []
    var active: Buffer?

    func show(_ b: Buffer) {
        if !tabs.contains(b) {
            let at = active.flatMap { tabs.firstIndex(of: $0) }.map { $0 + 1 } ?? tabs.count
            tabs.insert(b, at: at)
        }
        active = b
    }

    func remove(_ b: Buffer) {
        guard let i = tabs.firstIndex(of: b) else { return }
        tabs.remove(at: i)
        if active === b { active = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)] }
    }
}

/// A file-tree node. Folders scan in the background; `expanded` lives here (not in view @State) so it
/// survives row reuse and refreshes.
@Observable
final class FileNode: Identifiable {
    nonisolated static let hidden: Set<String> = [".git", ".DS_Store", "node_modules", ".build", ".swiftpm", ".hg", ".svn"]
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?  // nil until expanded
    var expanded = false        // kept on the node so it survives refreshes and row reuse
    @ObservationIgnored private var scannedDate: Date?
    @ObservationIgnored private var scanning = false
    var id: URL { url }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    /// Scan off the main thread; no-op while a scan is in flight.
    func load() {
        guard !scanning else { return }
        scanning = true
        let url = url
        Task {
            let (entries, date) = await Task.detached { (Self.scan(url), modificationDate(url)) }.value
            scanning = false
            scannedDate = date
            let byURL = Dictionary((children ?? []).map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
            children = entries.map { byURL[$0.url] ?? FileNode(url: $0.url, isDirectory: $0.isDirectory) }
        }
    }

    /// Re-scan loaded folders whose modification date changed (adding/removing an entry bumps it),
    /// keeping existing nodes so expansion state survives.
    func refresh() {
        guard let kids = children else { return }
        if modificationDate(url) != scannedDate { load() }
        kids.forEach { $0.refresh() }
    }

    /// The loaded node for `target`, if its folder chain is loaded.
    func find(_ target: URL) -> FileNode? {
        if url == target { return self }
        guard target.path.hasPrefix(url.path + "/") else { return nil }
        return children?.lazy.compactMap { $0.find(target) }.first
    }

    nonisolated private static func scan(_ url: URL) -> [(url: URL, isDirectory: Bool)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls
            .filter { !hidden.contains($0.lastPathComponent) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) }
            .sorted {
                $0.isDirectory != $1.isDirectory ? $0.isDirectory
                    : $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }
}

/// The window's state. Single window for v1.
// ponytail: one global workspace / one window; make per-window when multi-window lands.
@Observable
final class Workspace {
    static let shared = Workspace()

    var root: URL? {
        didSet {
            guard root != oldValue else { return }
            tree = root.map { FileNode(url: $0, isDirectory: true) }
            tree?.load()
            scheduleSave()
        }
    }
    var tree: FileNode?
    var sidebarVisible = true
    @ObservationIgnored private var closedURLs: [URL] = []  // ⇧⌘T, most recent last
    var treeSelection: URL?
    var groups: [EditorGroup] = [EditorGroup()]
    var layout: PaneLayout?
    var paneLayout: PaneLayout {
        let ids = groups.map(\.id)
        if let layout = layout?.retaining(Set(ids)), layout.leaves.count == ids.count, Set(layout.leaves) == Set(ids) { return layout }
        return .row(ids)
    }
    struct SplitDrop: Equatable { let groupID: UUID; let direction: SplitDirection }
    var splitDrop: SplitDrop?
    struct TabDrop: Equatable { let groupID: UUID; let beforeID: UUID?; let after: Bool }
    var tabDrop: TabDrop?
    @ObservationIgnored var paneFrames: [UUID: CGRect] = [:]
    var focusedID: UUID?
    @ObservationIgnored var draggingTabID: UUID?
    @ObservationIgnored var draggingGroupID: UUID?
    @ObservationIgnored var tabFrames: [UUID: [UUID: CGRect]] = [:]
    @ObservationIgnored var tabStripFrames: [UUID: CGRect] = [:]
    var verticalTabs = false { didSet { scheduleSave() } }
    var wrap = false { didSet { scheduleSave() } }
    var sidebarMode: SidebarMode = .files
    var statusMessage: String?
    var formatOnSave = UserDefaults.standard.bool(forKey: "formatOnSave") {
        didSet { UserDefaults.standard.set(formatOnSave, forKey: "formatOnSave") }
    }
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var formatting = Set<UUID>()
    let find = FindController()
    let projectSearch = ProjectSearch()

    enum SidebarMode: String { case files, search }

    @ObservationIgnored var presentAlert: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }
    @ObservationIgnored var savePanelURL: (NSSavePanel) -> URL? = { $0.runModal() == .OK ? $0.url : nil }
    @ObservationIgnored private let checkpointSleep: (Duration) async throws -> Void
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var editedSinceSave = Set<UUID>()

    var focusedGroup: EditorGroup { groups.first { $0.id == focusedID } ?? groups[0] }
    var active: Buffer? { focusedGroup.active }

    var allBuffers: [Buffer] {
        var seen = Set<UUID>()
        return groups.flatMap(\.tabs).filter { seen.insert($0.id).inserted }
    }

    init(store: SessionStore = .standard,
         checkpointSleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.store = store
        self.checkpointSleep = checkpointSleep
        restore()
        layout = paneLayout
    }

    // MARK: Files

    /// New untitled tab in `group` (default: the focused pane), which becomes focused.
    func newFile(in group: EditorGroup? = nil) {
        if let group { focusedID = group.id }
        let b = Buffer(url: nil)
        attach(b)
        focusedGroup.show(b)
        scheduleSave()
    }

    func open(_ url: URL) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            root = url
            return
        }
        if let b = allBuffers.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
            focusedGroup.show(b)
        } else {
            do {
                let b = try Buffer.load(url)
                attach(b)
                // Replace a lone untouched Untitled tab, like most editors.
                let g = focusedGroup
                if g.tabs.count == 1, let only = g.tabs.first, only.url == nil, !only.isDirty, only.storage.length == 0 {
                    g.remove(only)
                    tabFrames[g.id]?[only.id] = nil
                }
                g.show(b)
            } catch {
                alert("Can't open “\(url.lastPathComponent)”", error)
            }
        }
        scheduleSave()
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        if p.runModal() == .OK { p.urls.forEach(open) }
    }

    @discardableResult
    func save(_ b: Buffer) -> Bool {
        guard let url = b.url else { return saveAs(b) }
        let current = try? FileRevision.read(url)
        if b.conflict || current != b.diskRevision {
            b.conflict = true
            let alert = NSAlert()
            alert.messageText = "\(b.name) changed on disk"
            alert.informativeText = "Overwrite the external version with your edits?"
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Reload")
            let choice = presentAlert(alert)
            if choice == .alertThirdButtonReturn { try? b.reload(); return false }
            guard choice == .alertSecondButtonReturn else { return false }
        }
        return write(b, to: url, expected: current)
    }

    @discardableResult
    func saveAs(_ b: Buffer) -> Bool {
        let p = NSSavePanel()
        p.nameFieldStringValue = b.name
        if let dir = b.url?.deletingLastPathComponent() ?? root { p.directoryURL = dir }
        guard let url = savePanelURL(p) else { return false }
        return write(b, to: url)
    }

    func buffer(for url: URL) -> Buffer? {
        allBuffers.first { $0.url?.standardizedFileURL == url.standardizedFileURL }
    }

    /// Open `url` and select `range` in it (search results, tree "Show in Text").
    func reveal(_ url: URL, _ range: NSRange) {
        open(url)
        guard let b = buffer(for: url) else { return }
        if b.viewMode == .tree || b.viewMode == .preview { b.viewMode = .text }
        b.reveal = range
    }

    // MARK: Formatting

    func minifyJSON() {
        guard let b = active, b.language == .json else { return }
        do {
            b.replaceAll(with: JSON.format(try JSON.parse(b.text), indent: 0))
        } catch {
            alert("Can't minify “\(b.name)”", error)
        }
    }

    /// Format with the language's formatter (prettier, gofmt, rustfmt, …; built-in for JSON).
    /// `quiet` (format on save): no message when the language simply has no formatter.
    /// The result is discarded if the buffer was edited while the tool ran.
    /// With `selection` (and a non-empty selection) only the selected text is formatted.
    @discardableResult
    func format(_ b: Buffer, selection: Bool = false, quiet: Bool = false) async -> Bool {
        guard formatting.insert(b.id).inserted else { return false }
        defer { formatting.remove(b.id) }
        let range = selection && b.selection.length > 0 ? b.selection : nil
        let text = range.map { (b.text as NSString).substring(with: $0) } ?? b.text
        let revision = b.revision
        if !quiet { flash("Formatting…") }
        do {
            let path = await Task.detached { CodeFormatter.loginShellPath }.value
            var tool = ""
            let run: (String) async throws -> String = { s in
                let r = try await CodeFormatter.format(s, language: b.language, fileURL: b.url, searchPath: path)
                tool = r.tool
                return r.text
            }
            let out = try await range == nil ? run(text) : formatFragment(text, with: run)
            guard b.revision == revision else {
                flash("Not formatted: “\(b.name)” changed while formatting.")
                return false
            }
            if let range {
                if out != text { b.replace(range, with: out) }
            } else {
                b.replaceAll(with: out)
            }
            flash(out == text ? "Already formatted (\(tool))" : "Formatted \(range == nil ? "" : "selection ")with \(tool)")
            return true
        } catch {
            if quiet, case .noFormatter? = error as? CodeFormatter.Failure { return false }
            flash("\(error)")
            return false
        }
    }

    /// ⌘S: format first when Format on Save is on (a failing formatter never blocks the save).
    func saveCommand(_ b: Buffer) {
        guard formatOnSave else { save(b); return }
        Task {
            await format(b, quiet: true)
            save(b)
        }
    }

    func flash(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { statusMessage = nil }
        }
    }

    func saveAll() { allBuffers.filter(\.isDirty).forEach { save($0) } }

    private func write(_ b: Buffer, to url: URL, expected: FileRevision? = nil) -> Bool {
        // SQLite / Excel tabs hold no text: saving would overwrite the file with nothing.
        if b.language.isBinaryData { flash("“\(b.name)” is opened read-only"); return true }
        do {
            let expected = try expected ?? FileRevision.read(url)
            try b.write(to: url, matching: expected)
            scheduleSave()
            return true
        } catch TextFile.Failure.unrepresentable {
            let a = NSAlert()
            a.messageText = "“\(b.name)” contains characters that can't be saved in \(String.localizedName(of: b.encoding))."
            a.informativeText = "Save it as UTF-8 instead?"
            a.addButton(withTitle: "Save as UTF-8")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return false }
            b.encoding = .utf8
            return write(b, to: url, expected: expected)
        } catch {
            alert("Can't save “\(b.name)”", error)
            return false
        }
    }

    // MARK: Tabs & groups

    func close(_ b: Buffer, in g: EditorGroup) {
        let elsewhere = groups.contains { $0 !== g && $0.tabs.contains(b) }
        if b.isDirty && !elsewhere {
            let a = NSAlert()
            a.messageText = "Save changes to “\(b.name)”?"
            a.informativeText = "Your changes will be lost if you don't save them."
            a.addButton(withTitle: "Save")
            a.addButton(withTitle: "Cancel")
            a.addButton(withTitle: "Don't Save")
            switch a.runModal() {
            case .alertFirstButtonReturn: guard save(b) else { return }
            case .alertThirdButtonReturn: break
            default: return
            }
        }
        if let url = b.url, !elsewhere { closedURLs.removeAll { $0 == url }; closedURLs.append(url) }
        if draggingTabID == b.id { cancelTabDrag() }
        g.remove(b)
        tabFrames[g.id]?[b.id] = nil
        dropIfEmpty(g)
        scheduleSave()
    }

    // MARK: VS Code-style navigation

    /// ⇧⌘T: reopen the most recently closed file.
    func reopenClosed() {
        while let url = closedURLs.popLast() {
            if FileManager.default.fileExists(atPath: url.path) { open(url); return }
        }
        NSSound.beep()
    }

    /// ⌃Tab / ⌥⌘→ and back: cycle tabs in the focused pane.
    func cycleTab(_ step: Int) {
        let g = focusedGroup
        guard let a = g.active, let i = g.tabs.firstIndex(of: a), g.tabs.count > 1 else { return }
        g.active = g.tabs[(i + step + g.tabs.count) % g.tabs.count]
    }

    /// ⌘1…⌘9: focus pane n (1-based), creating the next one like VS Code when n is one past the end.
    func focusGroup(_ n: Int) {
        if n == groups.count + 1 { split(); return }
        guard groups.indices.contains(n - 1) else { return }
        focusedID = groups[n - 1].id
    }

    /// ⌃G: prompt for a line (optionally line:column) and jump there.
    func goToLine() {
        guard let b = active else { return }
        let a = NSAlert()
        a.messageText = "Go to Line"
        a.informativeText = "Line 1–\(b.lines.lineCount), optionally line:column"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "\(b.caretLine)"
        a.accessoryView = field
        a.addButton(withTitle: "Go")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard let line = parts.first else { return }
        let start = b.lines.start(ofLine: line)
        let lineEnd = line < b.lines.lineCount ? b.lines.start(ofLine: line + 1) - 1 : b.storage.length
        let col = min(max((parts.dropFirst().first ?? 1) - 1, 0), lineEnd - start)
        if b.viewMode == .tree || b.viewMode == .preview { b.viewMode = .text }
        b.reveal = NSRange(location: start + col, length: 0)
    }

    func closeOthers(_ b: Buffer, in g: EditorGroup) {
        for other in g.tabs where other !== b { close(other, in: g) }
    }

    enum Side { case left, right }

    func closeTabs(to side: Side, of b: Buffer, in g: EditorGroup) {
        guard let i = g.tabs.firstIndex(of: b) else { return }
        for other in side == .left ? Array(g.tabs[..<i]) : Array(g.tabs[(i + 1)...]) { close(other, in: g) }
    }

    func closeAll(in g: EditorGroup) {
        for b in g.tabs { close(b, in: g) }
    }

    /// ⌘W: close the focused tab, or the focused pane itself when it has no tabs.
    func closeActive() {
        if let b = active { close(b, in: focusedGroup) } else { dropIfEmpty(focusedGroup); scheduleSave() }
    }

    func split(_ direction: SplitDirection = .right, in pane: EditorGroup? = nil,
               moving id: UUID? = nil, from source: EditorGroup? = nil) {
        let target = pane ?? focusedGroup
        guard groups.contains(where: { $0 === target }) else { return }
        let buffer: Buffer?
        if let id {
            guard let source, groups.contains(where: { $0 === source }), source.tabs.contains(where: { $0.id == id }) else { return }
            buffer = source.tabs.first { $0.id == id }
        } else { buffer = target.active }
        let new = EditorGroup()
        if let buffer { new.show(buffer) }
        let tree = paneLayout.inserting(new.id, beside: target.id, direction: direction)
        let index = groups.firstIndex { $0 === target } ?? 0
        groups.insert(new, at: index + (direction.before ? 0 : 1))
        layout = tree
        if let source, let buffer, id != nil, source !== target || source.tabs.count > 1 {
            source.remove(buffer)
            tabFrames[source.id]?[buffer.id] = nil
            dropIfEmpty(source)
        }
        focusedID = new.id
        scheduleSave()
    }

    func resizeSplit(_ id: UUID, ratio: Double) {
        layout = paneLayout.resizing(id, ratio: ratio)
        scheduleSave()
    }

    func cancelTabDrag() {
        splitDrop = nil
        tabDrop = nil
        draggingTabID = nil
        draggingGroupID = nil
    }

    func finishTabDrag() {
        let edge = splitDrop, destination = tabDrop
        let id = draggingTabID, sourceID = draggingGroupID
        // Clear before changing the layout: removing the source pane cancels its gesture.
        cancelTabDrag()
        guard let id, let source = groups.first(where: { $0.id == sourceID }) else { return }
        if let edge, let target = groups.first(where: { $0.id == edge.groupID }) {
            split(edge.direction, in: target, moving: id, from: source)
        } else if let destination, let target = groups.first(where: { $0.id == destination.groupID }) {
            move(id, to: target, before: target.tabs.first { $0.id == destination.beforeID },
                 after: destination.after, from: source)
        }
    }

    func dropFiles(_ urls: [URL], in group: EditorGroup, direction: SplitDirection? = nil) {
        guard groups.contains(where: { $0 === group }) else { return }
        let files = urls.filter { $0.isFileURL && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
        guard !files.isEmpty else { return }
        focusedID = group.id
        if let direction {
            let new = EditorGroup()
            layout = paneLayout.inserting(new.id, beside: group.id, direction: direction)
            groups.append(new)
            focusedID = new.id
        }
        for url in files { open(url) }
        dropIfEmpty(focusedGroup)
    }

    /// Move a tab (by buffer id) into `target`, before `before` if given.
    @discardableResult
    func move(_ id: UUID, to target: EditorGroup, before: Buffer? = nil, after: Bool = false, from sourceGroup: EditorGroup? = nil) -> Bool {
        guard groups.contains(where: { $0 === target }),
              let source = sourceGroup ?? groups.first(where: { $0.tabs.contains { $0.id == id } }),
              groups.contains(where: { $0 === source }),
              let b = source.tabs.first(where: { $0.id == id }), b !== before else { return false }
        var reordered = target.tabs.filter { $0 !== b }
        let at = before.flatMap { reordered.firstIndex(of: $0) }.map { $0 + (after ? 1 : 0) } ?? reordered.count
        reordered.insert(b, at: at)
        if source === target {
            guard reordered.map(\.id) != target.tabs.map(\.id) else { return false }
            // Reordering must not select a neighbour and rebuild the active editor.
            target.tabs = reordered
        } else {
            source.remove(b)
            tabFrames[source.id]?[b.id] = nil
            target.tabs = reordered
            target.active = b
            focusedID = target.id
            dropIfEmpty(source)
        }
        scheduleSave()
        return true
    }

    func dragTab(to point: CGPoint) {
        var edge: SplitDrop?
        var destination: TabDrop?
        defer {
            // Avoid publishing an empty preview followed by the same preview on every pointer event.
            if splitDrop != edge { splitDrop = edge }
            if tabDrop != destination { tabDrop = destination }
        }
        guard let id = draggingTabID,
              let source = groups.first(where: { $0.id == draggingGroupID }) else { return }
        if let target = groups.first(where: { paneFrames[$0.id]?.contains(point) == true }),
           let frame = paneFrames[target.id] {
            if let direction = SplitDirection.edge(at: point, in: frame) {
                edge = SplitDrop(groupID: target.id, direction: direction)
            } else if target !== source {
                destination = TabDrop(groupID: target.id, beforeID: nil, after: false)
            }
            return
        }
        guard let target = groups.first(where: { tabStripFrames[$0.id]?.contains(point) == true }) else { return }
        let hit = tabFrames[target.id]?.first(where: { $0.value.contains(point) })
        let before = hit.flatMap { hit in target.tabs.first { $0.id == hit.key } }
        let after = hit.map { point.x > $0.value.midX } ?? false
        if target === source {
            if hit == nil, let last = target.tabs.last, let frame = tabFrames[target.id]?[last.id], point.x <= frame.maxX { return }
            move(id, to: target, before: before, after: after, from: source)
        } else {
            // Keep the drag source alive until release, including when it holds the last tab.
            destination = TabDrop(groupID: target.id, beforeID: before?.id, after: after)
        }
    }

    func dropIfEmpty(_ g: EditorGroup) {
        guard g.tabs.isEmpty, groups.count > 1, let i = groups.firstIndex(where: { $0 === g }) else { return }
        let tree = paneLayout
        groups.remove(at: i)
        paneFrames[g.id] = nil
        tabFrames[g.id] = nil
        tabStripFrames[g.id] = nil
        if draggingGroupID == g.id { cancelTabDrag() }
        layout = tree.retaining(Set(groups.map(\.id)))
        if focusedID == g.id { focusedID = groups[max(0, i - 1)].id }
    }

    // MARK: Disk changes

    /// Called when the app becomes active: reload clean buffers changed on disk, flag dirty ones.
    func checkDisk() {
        tree?.refresh()
        for b in allBuffers {
            guard let url = b.url, let d = modificationDate(url), d != b.diskDate else { continue }
            if b.isDirty { b.conflict = true } else { try? b.reload() }
        }
    }

    func keepMine(_ b: Buffer) {
        b.conflict = false
        b.diskDate = b.url.flatMap(modificationDate)
        b.diskRevision = b.url.flatMap { try? FileRevision.read($0) }
    }

    // MARK: Session (hot exit)

    private func attach(_ b: Buffer) {
        b.onEdit = { [weak self] buffer in self?.scheduleSave(edited: buffer) }
    }

    func scheduleSave(edited b: Buffer? = nil) {
        if let b { editedSinceSave.insert(b.id) }
        guard saveTask == nil else { return }
        let sleep = checkpointSleep
        saveTask = Task { [weak self] in
            try? await sleep(.seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSession()
        }
    }

    @discardableResult
    func saveSession() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        let buffers = allBuffers
        let session = Session(
            tabs: buffers.map {
                .init(id: $0.id, path: $0.url?.path, dirty: $0.isDirty, encoding: $0.encoding.rawValue,
                      lineEnding: $0.lineEnding, language: $0.language, selection: $0.selection.location, diskDate: $0.diskDate)
            },
            groups: groups.map { .init(tabs: $0.tabs.map(\.id), active: $0.active?.id, id: $0.id) },
            focused: groups.firstIndex { $0 === focusedGroup } ?? 0,
            root: root?.path, verticalTabs: verticalTabs, wrap: wrap, layout: paneLayout)
        let changed = Dictionary(uniqueKeysWithValues:
            buffers.filter { $0.isDirty && editedSinceSave.contains($0.id) }.map { ($0.id, $0.text) })
        do {
            try store.save(session, changed: changed)
            editedSinceSave.removeAll()
            return true
        } catch {
            flash("Recovery save failed: \(error.localizedDescription)")
            scheduleSave()
            return false
        }
    }

    private func restore() {
        guard let (s, texts) = store.load() else { return }
        var byID: [UUID: Buffer] = [:]
        for t in s.tabs {
            let url = t.path.map { URL(filePath: $0) }
            let b: Buffer
            if t.dirty, let text = texts[t.id] {
                b = Buffer(id: t.id, url: url, text: text)
                b.isDirty = true
                b.diskDate = t.diskDate
                if let url, let d = modificationDate(url), d != t.diskDate { b.conflict = true }
            } else if let url {
                guard let loaded = try? Buffer.load(url, id: t.id) else { continue }  // file gone
                b = loaded
            } else if !t.dirty {
                b = Buffer(id: t.id, url: nil)
            } else {
                continue
            }
            if t.dirty {
                b.encoding = String.Encoding(rawValue: t.encoding)
                b.lineEnding = t.lineEnding
            }
            if b.language != t.language { b.language = t.language }
            b.selection = NSRange(location: min(t.selection, b.storage.length), length: 0)
            attach(b)
            byID[t.id] = b
        }
        let restored = s.groups.compactMap { sg -> EditorGroup? in
            let g = EditorGroup(id: sg.id ?? UUID())
            g.tabs = sg.tabs.compactMap { byID[$0] }
            g.active = sg.active.flatMap { byID[$0] } ?? g.tabs.first
            return g.tabs.isEmpty ? nil : g
        }
        if !restored.isEmpty {
            groups = restored
            layout = s.layout?.retaining(Set(restored.map(\.id)))
            focusedID = restored[min(s.focused, restored.count - 1)].id
        }
        root = s.root.map { URL(filePath: $0, directoryHint: .isDirectory) }
        verticalTabs = s.verticalTabs
        wrap = s.wrap
        saveTask?.cancel()
        saveTask = nil
    }

    func alert(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = (error as? TextFile.Failure) == .binary ? "It looks like a binary file."
            : (error as? ParseError)?.description ?? error.localizedDescription
        a.runModal()
    }
}
