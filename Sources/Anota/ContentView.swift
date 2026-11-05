import AnotaCore
import SwiftUI

struct ContentView: View {
    @Bindable var ws: Workspace

    var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { ws.sidebarVisible ? .all : .detailOnly },
            set: { ws.sidebarVisible = $0 != .detailOnly })) {
            Sidebar(ws: ws)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                SplitPanes(items: ws.groups) { g in GroupView(ws: ws, group: g) }
                StatusBar(ws: ws)
            }
        }
        .navigationTitle(ws.active?.name ?? "Anota")
        .navigationSubtitle(subtitle)
        .toolbar {
            if let b = ws.active, b.modes.count > 1 {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: Binding(get: { b.viewMode }, set: { b.viewMode = $0 })) {
                        ForEach(b.modes, id: \.self) { m in Label(m.title, systemImage: m.symbol).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .help("View mode (⇧⌘V)")
                }
            }
            // Before the file name/path, next to the sidebar toggle.
            ToolbarItem(placement: .navigation) {
                Button { ws.verticalTabs.toggle() } label: {
                    Label("Tab Layout", systemImage: ws.verticalTabs ? "rectangle.split.1x2" : "sidebar.squares.left")
                }
                .help(ws.verticalTabs ? "Horizontal tabs" : "Vertical tabs")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $ws.wrap) { Label("Word Wrap", systemImage: "text.word.spacing") }
                    .help(ws.wrap ? "Turn off word wrap (⌥Z)" : "Wrap long lines (⌥Z)")
                Button { ws.split() } label: { Label("Split", systemImage: "square.split.2x1") }
                    .help("Split editor (⌘\\)")
                Button {
                    if let b = ws.active { Task { await ws.format(b, selection: true) } }
                } label: { Label("Format", systemImage: "text.alignleft") }
                    .help("Format Document (⌥⇧F), or the selection if there is one")
                    .disabled(ws.active == nil)
            }
        }
        .onChange(of: ws.active?.id, initial: true) { ws.find.attach(ws.active) }
        .onChange(of: ws.active?.revision) { ws.find.update() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            ws.checkDisk()
        }
    }

    private var subtitle: String {
        guard let dir = ws.active?.url?.deletingLastPathComponent().path else { return "" }
        return (dir as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: Sidebar

struct Sidebar: View {
    @Bindable var ws: Workspace

    var body: some View {
        VStack(spacing: 6) {
            Picker("Sidebar", selection: $ws.sidebarMode) {
                Image(systemName: "folder").help("Files").tag(Workspace.SidebarMode.files)
                Image(systemName: "magnifyingglass").help("Search (⇧⌘F)").tag(Workspace.SidebarMode.search)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            if ws.verticalTabs {
                tabs
                Divider()
            }
            if ws.sidebarMode == .search {
                SearchPanel(ws: ws, search: ws.projectSearch)
            } else {
                files
            }
        }
    }

    /// Vertical tabs, pinned above both the file tree and the search panel.
    /// Sized to its rows, capped so the panel below keeps most of the space.
    private var tabs: some View {
        let rows = ws.groups.reduce(0) { $0 + $1.tabs.count + 1 }
        return List {
            ForEach(Array(ws.groups.enumerated()), id: \.element.id) { i, g in
                Section {
                    ForEach(g.tabs) { b in VerticalTabRow(ws: ws, group: g, buffer: b) }
                        .onMove { from, to in g.tabs.move(fromOffsets: from, toOffset: to); ws.scheduleSave() }
                    // Empty strip under the tabs: double-click for a new file, like the horizontal bar.
                    Color.clear
                        .frame(height: 14)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { ws.newFile(in: g) }
                        .help("Double-click for a new file")
                } header: {
                    HStack {
                        Text(ws.groups.count > 1 ? "Tabs · Group \(i + 1)" : "Tabs")
                        Spacer()
                        NewTabButton { ws.newFile(in: g) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(height: min(CGFloat(rows) * 26 + 12 + CGFloat(ws.groups.count) * 14, 280))
    }

    private var files: some View {
        List(selection: $ws.treeSelection) {
            if let tree = ws.tree {
                Section(tree.url.lastPathComponent) {
                    ForEach(tree.children ?? []) { FileRow(node: $0) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if ws.tree == nil {
                VStack(spacing: 8) {
                    Text("No Folder Open").foregroundStyle(.secondary)
                    Button("Open Folder…") { ws.openPanel() }
                }
            }
        }
        .onChange(of: ws.treeSelection) { _, url in
            guard let url else { return }
            if let node = ws.tree?.find(url), node.isDirectory {
                // Clicking a folder's name toggles it (before, only the small chevron did, so clicks
                // on the name looked like the folder "randomly" refused to open).
                node.expanded.toggle()
                ws.treeSelection = nil
            } else {
                ws.open(url)
            }
        }
    }
}

struct FileRow: View {
    @Bindable var node: FileNode

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $node.expanded) {
                if let kids = node.children {
                    ForEach(kids) { FileRow(node: $0) }
                } else {
                    ProgressView().controlSize(.small)
                }
            } label: {
                Label(node.url.lastPathComponent, systemImage: "folder")
            }
            .tag(node.url)
            .onChange(of: node.expanded) { _, open in if open && node.children == nil { node.load() } }
        } else {
            Label(node.url.lastPathComponent, systemImage: Language.detect(node.url).symbol)
                .tag(node.url)
                .contextMenu { FileContextMenu(url: node.url) }
        }
    }
}

struct FileContextMenu: View {
    let url: URL
    var body: some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }
}

struct VerticalTabRow: View {
    let ws: Workspace
    let group: EditorGroup
    let buffer: Buffer
    @State private var hover = false

    var body: some View {
        let active = group.active === buffer
        HStack {
            Label(buffer.name, systemImage: buffer.language.symbol)
                .fontWeight(active ? .semibold : .regular)
            Spacer()
            CloseOrDirty(dirty: buffer.isDirty, visible: hover || active) { ws.close(buffer, in: group) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { group.active = buffer; ws.focusedID = group.id }
        .listRowBackground(active ? RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).padding(.horizontal, 8) : nil)
        .contextMenu { TabContextMenu(ws: ws, group: group, buffer: buffer) }
    }
}

// MARK: Tabs

struct TabBar: View {
    let ws: Workspace
    let group: EditorGroup
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(group.tabs) { b in
                    TabItem(buffer: b, active: group.active === b) { ws.close(b, in: group) }
                        .onTapGesture { group.active = b; ws.focusedID = group.id }
                        .draggable(b.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init) else { return false }
                            ws.move(id, to: group, before: b)
                            return true
                        }
                        .contextMenu { TabContextMenu(ws: ws, group: group, buffer: b) }
                }
                NewTabButton { ws.newFile(in: group) }  // like a browser's "+", right after the last tab
                // The empty rest of the strip: double-click for a new file.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { ws.newFile(in: group) }
            }
            .padding(.horizontal, 6)
            .frame(minWidth: width, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init) else { return false }
            ws.move(id, to: group)
            return true
        }
    }
}

/// "New file" in a tab strip: the empty-document icon from the empty editor, with a plus.
struct NewTabButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.badge.plus").hitTarget(width: 26, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("New File (⌘N) — or double-click an empty part of the tab bar")
    }
}

struct TabItem: View {
    let buffer: Buffer
    let active: Bool
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: buffer.language.symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(buffer.name).lineLimit(1)
            CloseOrDirty(dirty: buffer.isDirty, visible: hover || active, action: close)
        }
        .font(.system(size: 12))
        .foregroundStyle(active ? .primary : .secondary)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(Color.primary.opacity(active ? 0.09 : hover ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(buffer.url.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Untitled")
    }
}

/// Dirty dot that turns into a close button on hover.
struct CloseOrDirty: View {
    let dirty: Bool
    let visible: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if dirty && !hover {
                    Circle().fill(.secondary).frame(width: 7, height: 7)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(visible || hover ? 1 : 0)
                }
            }
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(dirty ? "Close (unsaved changes)" : "Close")
    }
}

struct TabContextMenu: View {
    let ws: Workspace
    let group: EditorGroup
    let buffer: Buffer

    var body: some View {
        Button("Close") { ws.close(buffer, in: group) }
        Button("Close Others") { ws.closeOthers(buffer, in: group) }
        Button("Close Tabs to the Left") { ws.closeTabs(to: .left, of: buffer, in: group) }
            .disabled(group.tabs.first === buffer)
        Button("Close Tabs to the Right") { ws.closeTabs(to: .right, of: buffer, in: group) }
            .disabled(group.tabs.last === buffer)
        Button("Close All") { ws.closeAll(in: group) }
        Divider()
        Button("Split Right") { group.active = buffer; ws.focusedID = group.id; ws.split() }
        if let url = buffer.url {
            Divider()
            FileContextMenu(url: url)
        }
    }
}

// MARK: Editor group

/// Side-by-side panes with draggable dividers. Unlike HSplitView, adding or removing a pane
/// re-divides the width equally, so a new split never opens squeezed to its minimum width.
struct SplitPanes<Item: Identifiable, Pane: View>: View {
    let items: [Item]
    @ViewBuilder let pane: (Item) -> Pane
    @State private var widths: [Item.ID: CGFloat] = [:]  // fractions; empty = equal
    @State private var dragStart: (CGFloat, CGFloat)?
    private let minWidth: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            let avail = max(geo.size.width - CGFloat(items.count - 1), 1)
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { divider(between: items[i - 1].id, and: item.id, avail: avail) }
                    pane(item).frame(width: avail * fraction(item.id))
                }
            }
        }
        .onChange(of: items.map(\.id)) { widths = [:] }
    }

    private func fraction(_ id: Item.ID) -> CGFloat { widths[id] ?? 1 / CGFloat(max(items.count, 1)) }

    private func divider(between a: Item.ID, and b: Item.ID, avail: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            let start = dragStart ?? (fraction(a), fraction(b))
                            dragStart = start
                            let total = start.0 + start.1, lo = min(minWidth / avail, total / 2)
                            let left = min(max(start.0 + g.translation.width / avail, lo), total - lo)
                            var w = Dictionary(uniqueKeysWithValues: items.map { ($0.id, fraction($0.id)) })
                            w[a] = left
                            w[b] = total - left
                            widths = w
                        }
                        .onEnded { _ in dragStart = nil })
            }
    }
}

struct GroupView: View {
    let ws: Workspace
    let group: EditorGroup

    var body: some View {
        VStack(spacing: 0) {
            if !ws.verticalTabs && !group.tabs.isEmpty {
                TabBar(ws: ws, group: group)
                Divider()
            }
            if let b = group.active {
                if b.conflict { ConflictBanner(ws: ws, buffer: b) }
                Group {
                    switch b.viewMode {
                    case .tree: TreeViewer(ws: ws, buffer: b)
                    case .preview: MarkdownPreview(buffer: b, revision: b.revision)
                    case .split:
                        HSplitView {
                            editor(b)
                            MarkdownPreview(buffer: b, revision: b.revision)
                        }
                    case .text: editor(b)
                    }
                }
                .id(b.id)
                .overlay(alignment: .topTrailing) {
                    if ws.find.visible && ws.focusedGroup === group && b.viewMode != .tree && b.viewMode != .preview {
                        FindBar(find: ws.find)
                    }
                }
            } else {
                EmptyEditor(ws: ws, group: group)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if ws.groups.count > 1 && ws.focusedGroup === group {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
    }
}

extension GroupView {
    fileprivate func editor(_ b: Buffer) -> some View {
        EditorView(buffer: b, wrap: ws.wrap, reveal: b.reveal) { ws.focusedID = group.id }
            .frame(minWidth: 200)
    }
}

extension Buffer.ViewMode {
    var title: String {
        switch self { case .text: "Text"; case .tree: "Tree"; case .preview: "Preview"; case .split: "Split" }
    }
    var symbol: String {
        switch self {
        case .text: "doc.plaintext"
        case .tree: "list.bullet.indent"
        case .preview: "eye"
        case .split: "rectangle.split.2x1"
        }
    }
}

struct ConflictBanner: View {
    let ws: Workspace
    let buffer: Buffer

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("“\(buffer.name)” changed on disk. You have unsaved changes.")
            Spacer()
            Button("Keep Mine") { ws.keepMine(buffer) }
            Button("Reload") { try? buffer.reload() }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.12))
    }
}

struct EmptyEditor: View {
    let ws: Workspace
    let group: EditorGroup
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            HStack {
                Button("New File") { ws.newFile() }
                Button("Open…") { ws.openPanel() }
                if ws.groups.count > 1 {
                    Button("Close Pane") { ws.dropIfEmpty(group); ws.scheduleSave() }
                }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { ws.focusedID = group.id }  // no text view here to take focus
    }
}

// MARK: Status bar

struct StatusBar: View {
    let ws: Workspace
    private static let encodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252, .macOSRoman, .shiftJIS]

    var body: some View {
        HStack(spacing: 16) {
            if let b = ws.active {
                Text("Ln \(b.caretLine), Col \(b.caretColumn)").monospacedDigit()
                if let m = ws.statusMessage {
                    Text(m).lineLimit(1).truncationMode(.tail).help(m)
                }
                Spacer()
                Menu(b.lineEnding.label) {
                    ForEach(LineEnding.allCases, id: \.self) { le in
                        Button(le.label) { b.lineEnding = le; b.markEdited() }
                    }
                }
                .fixedSize()
                Menu(String.localizedName(of: b.encoding)) {
                    ForEach(Self.encodings, id: \.rawValue) { e in
                        Button(String.localizedName(of: e)) { b.encoding = e; b.markEdited() }
                    }
                }
                .fixedSize()
                Menu(b.language.displayName) {
                    ForEach(Language.allCases) { l in
                        Button(l.displayName) { b.language = l; ws.scheduleSave() }
                    }
                }
                .fixedSize()
            } else {
                Spacer()
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension Language {
    var symbol: String {
        switch self {
        case .swift: "swift"
        case .json: "curlybraces"
        case .markdown: "text.alignleft"
        case .yaml, .toml, .ini: "gearshape"
        case .dotenv: "key"
        case .log: "list.bullet.rectangle"
        case .batch, .powershell: "terminal.fill"
        case .html, .xml: "chevron.left.forwardslash.chevron.right"
        case .shell: "terminal"
        case .css: "paintbrush"
        case .sql: "cylinder"
        case .plain: "doc.text"
        default: "doc.plaintext"
        }
    }
}
