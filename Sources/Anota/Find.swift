import AnotaCore
import SwiftUI

/// In-file find/replace (VS Code style). Works on the focused buffer; highlights every
/// match with temporary attributes on each layout manager showing that buffer.
@Observable
final class FindController {
    var visible = false
    var showReplace = false
    var options = SearchOptions() {
        didSet { if options != oldValue { update(reveal: options.query != oldValue.query) } }
    }
    var replacement = ""
    var matches: [NSRange] = []
    var current: Int?
    var invalid = false
    var focusToken = 0  // bump to focus the find field
    /// The bar's frame in window content coordinates (top-left origin), so the editor underneath
    /// can show an arrow instead of its I-beam while the pointer is over the bar.
    @ObservationIgnored var barFrame = CGRect.zero

    @ObservationIgnored private weak var buffer: Buffer?
    @ObservationIgnored private var highlighted: [NSRange] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func open(replace: Bool, buffer: Buffer?) {
        if let b = buffer, b.selection.length > 0, b.selection.length < 200 {
            let s = (b.text as NSString).substring(with: b.selection)
            if !s.contains("\n") { options.query = s }
        }
        visible = true
        showReplace = replace
        attach(buffer)
        focusToken += 1
    }

    func close() {
        visible = false
        barFrame = .zero
        clearHighlight()
        matches = []
        current = nil
    }

    func attach(_ b: Buffer?) {
        guard b !== buffer else { return }
        clearHighlight()
        buffer = b
        update()
    }

    func useSelection(_ b: Buffer?) {
        guard let b, b.selection.length > 0 else { return }
        options.query = (b.text as NSString).substring(with: b.selection)
    }

    /// Recompute matches (query/options/text changed). Matching runs off the main thread so typing
    /// stays smooth on big files; a newer call cancels an older one. `reveal` jumps to the nearest
    /// match (as you type the query), like VS Code.
    func update(reveal: Bool = false) {
        task?.cancel()
        guard visible, let b = buffer, !options.query.isEmpty else {
            clearHighlight(); matches = []; current = nil; invalid = false; return
        }
        let (text, o) = (b.text, options)
        task = Task {
            let found = await Task.detached { Self.search(text, o) }.value
            guard !Task.isCancelled, b === buffer, b.text == text else { return }
            apply(found, reveal: reveal)
        }
    }

    /// Synchronous variant for replace, which needs fresh matches immediately.
    private func updateNow() {
        task?.cancel()
        guard let b = buffer, !options.query.isEmpty else { return }
        apply(Self.search(b.text, options), reveal: false)
    }

    private func apply(_ found: [NSRange]?, reveal: Bool) {
        guard let b = buffer else { return }
        invalid = found == nil
        matches = found ?? []
        current = matches.firstIndex { $0.location >= b.selection.location } ?? (matches.isEmpty ? nil : 0)
        highlight()
        if reveal, let i = current { b.reveal = matches[i] }
    }

    /// nil = invalid regex. ponytail: capped at 10K matches.
    nonisolated private static func search(_ text: String, _ o: SearchOptions) -> [NSRange]? {
        guard let re = try? o.compile() else { return nil }
        var ranges: [NSRange] = []
        let deadline = Date().addingTimeInterval(2)
        re.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            guard ranges.count < 10_000, !Task.isCancelled, Date() < deadline else { stop.pointee = true; return }
            if let match, match.range.length > 0 { ranges.append(match.range) }
        }
        return ranges
    }

    func highlight() {
        clearHighlight()
        guard visible, let b = buffer else { return }
        let color = NSColor.findHighlightColor.withAlphaComponent(0.35)
        for lm in b.storage.layoutManagers {
            for r in matches { lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r) }
        }
        highlighted = matches
    }

    private func clearHighlight() {
        guard let b = buffer, !highlighted.isEmpty else { return }
        let full = NSRange(location: 0, length: b.storage.length)
        for lm in b.storage.layoutManagers { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full) }
        highlighted = []
    }

    func step(_ forward: Bool) {
        guard !matches.isEmpty, let b = buffer else { NSSound.beep(); return }
        let loc = b.selection.location
        if forward {
            current = matches.firstIndex { $0.location > loc } ?? 0
        } else {
            current = matches.lastIndex { $0.location < loc } ?? matches.count - 1
        }
        b.reveal = matches[current!]
    }

    func replaceCurrent() {
        guard let b = buffer, let i = current, i < matches.count, let re = try? options.compile(),
              let m = re.firstMatch(in: b.text, options: [.withTransparentBounds], range: matches[i]) else { return }
        b.replace(m.range, with: options.replacement(for: m, in: b.text, with: replacement, using: re))
        b.selection = NSRange(location: m.range.location, length: 0)
        updateNow()
        if !matches.isEmpty { b.reveal = matches[current ?? 0] }
    }

    func replaceAll() {
        guard let b = buffer, let (text, n) = try? options.replaceAll(in: b.text, with: replacement), n > 0 else { return }
        b.replaceAll(with: text)  // one undo step
        updateNow()
    }
}

struct FindBar: View {
    @Bindable var find: FindController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { find.showReplace.toggle() } label: {
                    Image(systemName: find.showReplace ? "chevron.down" : "chevron.right").hitTarget(width: 16)
                }
                .buttonStyle(.plain)
                .help("Toggle Replace")
                TextField("Find", text: $find.options.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($focused)
                    .onSubmit { find.step(true) }
                    .foregroundStyle(find.invalid ? .red : .primary)
                OptionToggles(options: $find.options)
                Text(status).font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 64)
                Button { find.step(false) } label: { Image(systemName: "chevron.up").hitTarget() }.help("Previous (⇧⌘G)")
                Button { find.step(true) } label: { Image(systemName: "chevron.down").hitTarget() }.help("Next (⌘G)")
                Button { find.close() } label: { Image(systemName: "xmark").hitTarget() }.help("Close (Esc)")
            }
            if find.showReplace {
                HStack(spacing: 6) {
                    Spacer().frame(width: 16)
                    TextField("Replace", text: $find.replacement)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { find.replaceCurrent() }
                    Toggle("AB", isOn: $find.options.preserveCase).toggleStyle(OptionToggleStyle()).help("Preserve Case")
                    Button("Replace") { find.replaceCurrent() }
                    Button("All") { find.replaceAll() }.help("Replace All")
                }
            }
        }
        .buttonStyle(.borderless)
        .toggleStyle(.button)
        .controlSize(.small)
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .padding(10)
        .onExitCommand { find.close() }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { find.barFrame = $0 }
        .onDisappear { find.barFrame = .zero }
        .task(id: find.focusToken) {
            // Wait a runloop turn: the bar must be in the window, and the editor gives up focus first.
            await Task.yield()
            NSApp.keyWindow?.makeFirstResponder(nil)
            focused = true
        }
    }

    private var status: String {
        if find.options.query.isEmpty { return "" }
        if find.invalid { return "Bad regex" }
        if find.matches.isEmpty { return "No results" }
        return "\((find.current ?? 0) + 1) of \(find.matches.count)\(find.matches.count == 10_000 ? "+" : "")"
    }
}

struct OptionToggles: View {
    @Binding var options: SearchOptions
    var body: some View {
        HStack(spacing: 2) {
            Toggle("Aa", isOn: $options.caseSensitive).help("Match Case")
            Toggle("ab", isOn: $options.wholeWord).underline().help("Match Whole Word")
            Toggle(".*", isOn: $options.regex).help("Use Regular Expression")
        }
        .toggleStyle(OptionToggleStyle())
    }
}

/// VS Code-style option chip: the whole 26×22 box is clickable and shows an accent fill when on.
struct OptionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                .hitTarget(width: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(configuration.isOn ? Color.accentColor.opacity(0.18) : .clear)
                        .strokeBorder(configuration.isOn ? Color.accentColor.opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

extension View {
    /// Pad a small icon/label to a comfortable, fully clickable box.
    func hitTarget(width: CGFloat = 24, height: CGFloat = 22) -> some View {
        frame(width: width, height: height).contentShape(Rectangle())
    }
}

// MARK: Find in files

@Observable
final class ProjectSearch {
    var options = SearchOptions()
    var replacement = ""
    var include = ""
    var exclude = ""
    var results: [FileMatches] = []
    var truncated = false
    var completedOptions: SearchOptions?
    var completedInclude = ""
    var completedExclude = ""
    var completedRoot: URL?
    var canReplace: Bool { !running && !results.isEmpty && options == completedOptions && include == completedInclude && exclude == completedExclude }
    var running = false
    var error: String?
    var focusToken = 0
    @ObservationIgnored var confirmReplacement: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }

    @ObservationIgnored private var task: Task<Void, Never>?

    var total: Int { results.reduce(0) { $0 + $1.matches.count } }

    func run(root: URL?) {
        task?.cancel()
        error = nil
        guard let root, !options.query.isEmpty else { results = []; running = false; return }
        running = true
        results = []
        let included = include, excluded = exclude
        let (o, inc, exc) = (options, FileSearch.globs(include), FileSearch.globs(exclude))
        task = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))  // debounce typing
                let r = try await FileSearch.report(root: root, options: o, include: inc, exclude: exc)
                guard !Task.isCancelled else { return }
                completedOptions = o
                completedInclude = included
                completedExclude = excluded
                completedRoot = root
                results = r.files
                truncated = r.truncated
            } catch is CancellationError {
                return
            } catch {
                self.error = "Invalid search pattern"
                results = []
            }
            running = false
        }
    }

    /// Replace in every result file. Open buffers are edited in place (undoable, left unsaved);
    /// other files are rewritten on disk.
    func replaceAll(in ws: Workspace) {
        let files = results
        guard canReplace, ws.root == completedRoot else { return }
        let appliedOptions = options, template = replacement
        let a = NSAlert()
        a.messageText = "Replace \(total) occurrences in \(files.count) files with “\(replacement)”?"
        a.informativeText = "Files that aren't open are changed on disk and can't be undone."
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Cancel")
        guard confirmReplacement(a) == .alertFirstButtonReturn, canReplace, ws.root == completedRoot, options == appliedOptions, replacement == template else { return }
        var failed: [String] = []
        for f in files {
            if let b = ws.buffer(for: f.url) {
                guard b.text == f.text else { failed.append(f.url.lastPathComponent); continue }
                if let text = try? f.replacing(options: options, template: replacement) { b.replaceAll(with: text) }
            } else {
                do {
                    let version = try FileRevision.read(f.url)
                    var file = try TextFile.read(f.url)
                    guard file.text == f.text, !f.url.hasDirectoryPath, (try f.url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { failed.append(f.url.lastPathComponent); continue }
                    file.text = try f.replacing(options: options, template: replacement)
                    try file.write(to: f.url, matching: version)
                } catch {
                    failed.append(f.url.lastPathComponent)
                }
            }
        }
        run(root: ws.root)
        if !failed.isEmpty { error = "Files changed or could not be written: " + failed.joined(separator: ", ") }
    }
}

struct SearchPanel: View {
    @Bindable var ws: Workspace
    @Bindable var search: ProjectSearch
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Search", text: $search.options.query)
                    .focused($focused)
                OptionToggles(options: $search.options)
            }
            HStack {
                TextField("Replace", text: $search.replacement)
                Toggle("AB", isOn: $search.options.preserveCase).help("Preserve Case")
                Button { search.replaceAll(in: ws) } label: { Image(systemName: "text.badge.checkmark") }
                    .help("Replace All")
                    .disabled(!search.canReplace)
            }
            TextField("Files to include (e.g. *.swift, src/*)", text: $search.include)
            TextField("Files to exclude", text: $search.exclude)
            HStack {
                if search.running { ProgressView().controlSize(.mini) }
                Text(summary).font(.caption).foregroundStyle(search.error == nil ? Color.secondary : Color.red)
            }
        }
        .textFieldStyle(.roundedBorder)
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .onChange(of: ws.root, initial: true) { search.run(root: ws.root) }
        .onChange(of: search.options) { search.run(root: ws.root) }
        .onChange(of: search.include) { search.run(root: ws.root) }
        .onChange(of: search.exclude) { search.run(root: ws.root) }
        .onChange(of: search.focusToken, initial: true) { focused = true }

        List {
            ForEach(search.results) { f in
                DisclosureGroup(isExpanded: .constant(true)) {
                    ForEach(f.matches) { m in
                        MatchRow(match: m, replacement: preview(m, in: f.text))
                            .contentShape(Rectangle())
                            .onTapGesture { ws.reveal(f.url, m.range) }
                    }
                } label: {
                    HStack {
                        Label(f.url.lastPathComponent, systemImage: Language.detect(f.url).symbol)
                        Text(relative(f.url)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Text("\(f.matches.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func preview(_ match: LineMatch, in text: String) -> String? {
        guard search.canReplace, let value = try? match.replacement(in: text, options: search.options, template: search.replacement) else { return nil }
        return value.isEmpty ? "∅" : value
    }

    private var summary: String {
        if let e = search.error { return e }
        if ws.root == nil { return "Open a folder to search in files." }
        if search.options.query.isEmpty { return "" }
        if search.running && search.results.isEmpty { return "Searching…" }
        return "\(search.total) results in \(search.results.count) files" + (search.truncated ? " · Partial results (search budget reached)" : "")
    }

    private func relative(_ url: URL) -> String {
        guard let root = ws.root?.standardizedFileURL.path else { return "" }
        let dir = url.deletingLastPathComponent().standardizedFileURL.path
        return dir.hasPrefix(root) ? String(dir.dropFirst(root.count)).trimmingCharacters(in: .init(charactersIn: "/")) : dir
    }
}

struct MatchRow: View {
    let match: LineMatch
    let replacement: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(match.line)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit().frame(minWidth: 24, alignment: .trailing)
            Text(attributed).lineLimit(1).font(.system(size: 11, design: .monospaced))
        }
    }

    private var attributed: AttributedString {
        let ns = match.lineText as NSString
        let r = match.rangeInLine
        let before = ns.substring(to: r.location)
        let trimmed = before.drop { $0 == " " || $0 == "\t" }
        var out = AttributedString(String(trimmed.suffix(40)))
        var hit = AttributedString(ns.substring(with: r))
        hit.backgroundColor = .yellow.opacity(0.35)
        if let replacement {
            hit.strikethroughStyle = .single
            var new = AttributedString(replacement)
            new.backgroundColor = .green.opacity(0.3)
            hit += new
        }
        out += hit
        out += AttributedString(ns.substring(from: NSMaxRange(r)))
        return out
    }
}
