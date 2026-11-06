import AnotaCore
import SwiftUI

/// Firefox-style structured viewer for JSON / INI / .env / plist. Re-parses on each text change.
struct TreeViewer: View {
    let ws: Workspace
    let buffer: Buffer
    @State private var tree: Result<TreeItem, ParseError>?
    @State private var filter = ""
    @State private var expanded: Set<String> = []
    @State private var editing: TreeItem?
    @State private var editText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                TextField("Filter keys and values", text: $filter).textFieldStyle(.plain)
                Spacer()
                Button("Expand All") { if case .success(let t)? = tree { expanded = Set(t.containerIDs) } }
                Button("Collapse All") { expanded = [] }
                if buffer.language == .json {
                    Button("Format") { Task { await ws.format(buffer) } }.help("Format Document (⌥⇧F)")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: buffer.revision) {
            let text = buffer.text, language = buffer.language, plist = buffer.isPlist, revision = buffer.revision
            let parsed = await Self.parse(text: text, language: language, plist: plist)
            guard !Task.isCancelled, buffer.revision == revision else { return }
            if tree == nil, case .success(let t) = parsed {
                // Open the top two levels on first show.
                expanded = Set([t.id] + (t.children ?? []).filter { $0.children != nil }.map(\.id))
            }
            tree = parsed
        }
        .alert("Edit Value", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Value", text: $editText)
            Button("Save") { commitEdit() }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text(editing?.id ?? "")
        }
    }

    static func parse(text: String, language: Language, plist: Bool) async -> Result<TreeItem, ParseError> {
        await Task.detached {
            Result { () throws -> Node in
                if plist { return try Plist.parse(text) }
                switch language {
                case .ini, .dotenv: return INI.parse(text)
                case .yaml: return try YAML.parse(text)
                case .toml: return try TOML.parse(text)
                default: return try JSON.parse(text)
                }
            }.map { TreeItem.build($0) }
             .mapError { $0 as? ParseError ?? ParseError(message: "\($0)", line: 1, column: 1) }
        }.value
    }

    @ViewBuilder private var content: some View {
        switch tree {
        case nil:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let e):
            ContentUnavailableView {
                Label("Can't parse \(buffer.language.displayName)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(e.description)
            } actions: {
                Button("Show in Text") {
                    buffer.viewMode = .text
                    buffer.reveal = offset(line: e.line, column: e.column)
                }
            }
        case .success(let root):
            if let shown = root.filtered(filter) {
                List {
                    if let kids = shown.children {
                        ForEach(kids) { TreeRow(item: $0, expanded: $expanded, forceOpen: !filter.isEmpty, actions: actions) }
                    } else {
                        TreeRow(item: shown, expanded: $expanded, forceOpen: false, actions: actions)
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            } else {
                ContentUnavailableView.search(text: filter)
            }
        }
    }

    private var actions: TreeActions {
        TreeActions(
            copyValue: { item in
                let s = item.range.map { (buffer.text as NSString).substring(with: $0) } ?? item.displayValue
                copy(item.children == nil && buffer.language != .json ? unquoted(item) : s)
            },
            copyPath: { copy($0.id) },
            showInText: { item in
                guard let r = item.range else { return }
                buffer.viewMode = .text
                buffer.reveal = r
            },
            edit: buffer.language == .json ? { item in
                editText = unquoted(item)
                editing = item
            } : nil)
    }

    private func unquoted(_ item: TreeItem) -> String {
        if case .string(let s) = item.value { return s }
        return item.displayValue
    }

    private func commitEdit() {
        guard let item = editing, let range = item.range else { return }
        editing = nil
        let literal: String
        if case .string = item.value { literal = JSON.quote(editText) } else { literal = editText }
        guard (try? JSON.parse(literal)) != nil else { NSSound.beep(); return }  // must stay valid JSON
        buffer.replace(range, with: literal)
    }

    private func offset(line: Int, column: Int) -> NSRange {
        let ns = buffer.text as NSString
        var loc = 0
        for _ in 1..<max(line, 1) {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(r)
        }
        return NSRange(location: min(loc + column - 1, ns.length), length: 0)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct TreeActions {
    let copyValue: (TreeItem) -> Void
    let copyPath: (TreeItem) -> Void
    let showInText: (TreeItem) -> Void
    let edit: ((TreeItem) -> Void)?
}

struct TreeRow: View {
    let item: TreeItem
    @Binding var expanded: Set<String>
    let forceOpen: Bool
    let actions: TreeActions

    var body: some View {
        if let kids = item.children, !kids.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { forceOpen || expanded.contains(item.id) },
                set: { if $0 { expanded.insert(item.id) } else { expanded.remove(item.id) } })
            ) {
                ForEach(kids) { TreeRow(item: $0, expanded: $expanded, forceOpen: forceOpen, actions: actions) }
            } label: { label }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(key).foregroundStyle(item.key == nil ? Color.secondary : Color(nsColor: .systemBlue))
            Text(item.displayValue)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if item.children == nil { actions.edit?(item) } }
        .contextMenu {
            Button("Copy Value") { actions.copyValue(item) }
            Button("Copy Path") { actions.copyPath(item) }
            if item.range != nil { Button("Show in Text") { actions.showInText(item) } }
            if let edit = actions.edit, item.children == nil, item.range != nil {
                Divider()
                Button("Edit Value…") { edit(item) }
            }
        }
        .help(item.id)
    }

    private var key: String {
        if let k = item.key { return k + ":" }
        guard let open = item.id.lastIndex(of: "[") else { return "" }
        return String(item.id[item.id.index(after: open)...].dropLast()) + ":"
    }

    private var valueColor: Color {
        switch item.value {
        case .object, .array: .secondary
        case .string: Color(nsColor: .systemRed)
        case .number: Color(nsColor: .systemPurple)
        case .bool, .null: Color(nsColor: .systemPink)
        }
    }
}
