import AnotaCore
import SwiftUI
import UniformTypeIdentifiers

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
                PaneLayoutView(ws: ws, node: ws.paneLayout, selectionID: ws.active?.id)
                StatusBar(ws: ws).id(ws.active?.id)
            }
        }
        .navigationTitle(ws.active?.name ?? "Anota")
        .navigationSubtitle(subtitle)
        .toolbar {
            // Always present, content conditional: adding/removing the item itself, or changing the
            // segment count in place, left a stale glass capsule (e.g. 3 icons for a 2-mode file).
            ToolbarItem(placement: .principal) {
                if let b = ws.active, b.modes.count > 1 {
                    Picker("View", selection: Binding(get: { b.viewMode }, set: { b.viewMode = $0 })) {
                        ForEach(b.modes, id: \.self) { m in Label(m.title, systemImage: m.symbol).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .help("View mode (⇧⌘V)")
                    .id(b.modes.map(\.rawValue).joined(separator: ","))  // rebuild when the set of modes changes
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
                Menu {
                    ForEach(SplitDirection.allCases) { direction in
                        Button("Split " + direction.title) { ws.split(direction) }
                    }
                } label: { Label("Split", systemImage: "square.split.2x1") }
                .help("Split editor left, right, top, or bottom")
                Button {
                    if let b = ws.active { Task { await ws.format(b, selection: true) } }
                } label: { Label("Format", systemImage: "text.alignleft") }
                    .help("Format Document (⌥⇧F), or the selection if there is one")
                    .disabled(ws.active == nil)
            }
        }
        .onChange(of: ws.active?.id, initial: true) {
            ws.find.attach(ws.active)
            // Keep the tree's selection on the active file (nil when it's outside the folder). Otherwise
            // the tree still "selects" an older file and clicking it again changes nothing, so it won't open.
            let url = ws.active?.url
            ws.treeSelection = url.flatMap { ws.tree?.find($0) } != nil ? url : nil
        }
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
        // Selection is only a highlight that follows the active tab (set in ContentView). Rows open files
        // on click themselves: driving opens from selection changes let the list write back an old
        // selection and re-open that file, so a tab outside the folder couldn't be selected.
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { node.expanded.toggle() }  // the name toggles too, not only the chevron
            }
            .tag(node.url)
            .onChange(of: node.expanded) { _, open in if open && node.children == nil { node.load() } }
        } else {
            Label(node.url.lastPathComponent, systemImage: Language.detect(node.url).symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { Workspace.shared.open(node.url) }
                .tag(node.url)
                .contextMenu { FileContextMenu(url: node.url) }
                .onDrag { NSItemProvider(object: node.url as NSURL) }
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
    @GestureState private var dragActive = false

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
        .onChange(of: dragActive) { _, active in
            if !active { ws.cancelTabDrag() }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragActive) { _, active, _ in active = true }
            .onChanged { value in
                if ws.draggingTabID != buffer.id || ws.draggingGroupID != group.id {
                    ws.cancelTabDrag()
                    ws.draggingTabID = buffer.id
                    ws.draggingGroupID = group.id
                }
                ws.dragTab(to: value.location)
            }
            .onEnded { value in ws.dragTab(to: value.location); ws.finishTabDrag() })
    }
}

// MARK: Tabs

struct TabBar: View {
    let ws: Workspace
    let group: EditorGroup
    var selectionID: UUID? = nil
    @GestureState private var dragActive = false
    @State private var width: CGFloat = 0
    @State private var dragging: UUID?
    @State private var pointerX: CGFloat = 0
    @State private var pointerY: CGFloat = 0
    @State private var grabX: CGFloat = 0
    @State private var dragWidth: CGFloat = 0

    var body: some View {
        // Read the active tab here, in body itself: read only inside the ForEach closure it wasn't tracked when
        // a file was opened from outside (Finder / Dock), so the new tab never drew as active.
        let active = group.active
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(group.tabs) { b in
                        DraggableTab(ws: ws, group: group, buffer: b, selected: active === b)
                            .opacity(dragging == b.id ? 0 : 1)
                            .id(b.id)
                    }
                    NewTabButton { ws.newFile(in: group) }
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { ws.newFile(in: group) }
                }
                .animation(.smooth(duration: 0.12), value: group.tabs.map(\.id))
                .padding(.horizontal, 6)
                .frame(minWidth: width, maxHeight: .infinity, alignment: .leading)
            }
            .onChange(of: active?.id, initial: true) { _, id in
                if let id {
                    Task { @MainActor in
                        await Task.yield()
                        guard group.active?.id == id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if let id = dragging, let buffer = ws.allBuffers.first(where: { $0.id == id }) {
                TabItem(buffer: buffer, active: true) {}
                    .frame(width: dragWidth, height: 34)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .offset(x: pointerX - grabX - (ws.tabStripFrames[group.id]?.minX ?? 0),
                            y: pointerY - (ws.tabStripFrames[group.id]?.midY ?? 0))
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if ws.tabDrop?.groupID == group.id {
                Rectangle().fill(Color.accentColor).frame(height: 2).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], delegate: WorkspaceFileDrop(ws: ws, group: group, allowSplit: false))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { ws.tabStripFrames[group.id] = $0 }
        .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragActive) { _, active, _ in active = true }
            .onChanged { value in
                if dragging == nil,
                   let tab = ws.tabFrames[group.id]?.first(where: { $0.value.contains(value.startLocation) }) {
                    ws.cancelTabDrag()
                    dragging = tab.key
                    grabX = value.startLocation.x - tab.value.minX
                    dragWidth = tab.value.width
                    ws.draggingTabID = tab.key
                    ws.draggingGroupID = group.id
                }
                pointerX = value.location.x
                pointerY = value.location.y
                ws.dragTab(to: value.location)
            }
            .onEnded { value in
                ws.dragTab(to: value.location)
                dragging = nil
                ws.finishTabDrag()
            })
        .onChange(of: dragActive) { _, active in
            if !active { dragging = nil; ws.cancelTabDrag() }
        }
    }
}

private struct DraggableTab: View {
    let ws: Workspace
    let group: EditorGroup
    let buffer: Buffer
    let selected: Bool

    var body: some View {
        let active = selected
        TabItem(buffer: buffer, active: active) { ws.close(buffer, in: group) }
            .onTapGesture { group.active = buffer; ws.focusedID = group.id }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { ws.tabFrames[group.id, default: [:]][buffer.id] = $0 }
            .contextMenu { TabContextMenu(ws: ws, group: group, buffer: buffer) }
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
        ForEach(SplitDirection.allCases) { direction in
            Button("Split " + direction.title) {
                group.active = buffer
                ws.split(direction, in: group)
            }
        }
        if let url = buffer.url {
            Divider()
            FileContextMenu(url: url)
        }
    }
}

// MARK: Editor group

struct GroupView: View {
    let ws: Workspace
    let group: EditorGroup
    let selectionID: UUID?

    init(ws: Workspace, group: EditorGroup) {
        self.ws = ws
        self.group = group
        self.selectionID = group.active?.id
    }

    var body: some View {
        let active = group.active
        return VStack(spacing: 0) {
            if !ws.verticalTabs && !group.tabs.isEmpty {
                TabBar(ws: ws, group: group, selectionID: active?.id)
                Divider()
            }
            if let b = active {
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
                    case .grid: DataView(ws: ws, buffer: b)
                    }
                }
                .id(b.id)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { ws.paneFrames[group.id] = $0 }
                .overlay { splitPreview }
                .onDrop(of: [UTType.fileURL], delegate: WorkspaceFileDrop(ws: ws, group: group))
                .overlay(alignment: .topTrailing) {
                    if ws.find.visible && ws.focusedGroup === group && [.text, .split].contains(b.viewMode) {
                        FindBar(find: ws.find)
                    }
                }
            } else {
                EmptyEditor(ws: ws, group: group)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { ws.paneFrames[group.id] = $0 }
                    .overlay { splitPreview }
                    .onDrop(of: [UTType.fileURL], delegate: WorkspaceFileDrop(ws: ws, group: group))
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
    @ViewBuilder fileprivate var splitPreview: some View {
        if let drop = ws.splitDrop, drop.groupID == group.id {
            GeometryReader { geometry in
                let direction = drop.direction
                let width = geometry.size.width * (direction.horizontal ? 0.5 : 1)
                let height = geometry.size.height * (direction.horizontal ? 1 : 0.5)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: width, height: height)
                    .position(x: direction == .right ? geometry.size.width - width / 2 : width / 2,
                              y: direction == .bottom ? geometry.size.height - height / 2 : height / 2)
            }
            .allowsHitTesting(false)
        } else if ws.tabDrop?.groupID == group.id {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2))
                .allowsHitTesting(false)
        }
    }
}

extension GroupView {
    fileprivate func editor(_ b: Buffer) -> some View {
        EditorView(buffer: b, wrap: ws.wrap, reveal: b.reveal, isActive: { group.active === b && ws.focusedGroup === group }) { ws.focusedID = group.id; ws.find.highlight() }
            .frame(minWidth: 200)
    }
}

extension Buffer.ViewMode {
    var title: String {
        switch self { case .text: "Text"; case .tree: "Tree"; case .preview: "Preview"; case .split: "Split"; case .grid: "Grid" }
    }
    var symbol: String {
        switch self {
        case .text: "doc.plaintext"
        case .tree: "list.bullet.indent"
        case .preview: "eye"
        case .split: "rectangle.split.2x1"
        case .grid: "tablecells"
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
        case .csv, .tsv, .excel: "tablecells"
        case .jsonl: "list.bullet.rectangle.portrait"
        case .sqlite: "cylinder.split.1x2"
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
