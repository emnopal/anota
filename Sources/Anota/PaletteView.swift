import AnotaCore
import SwiftUI

struct PaletteView: View {
    let ws: Workspace
    let mode: Workspace.PaletteMode
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    private var commands: [(String, () -> Void)] {
        [("New File", { ws.newFile() }), ("Open File or Folder…", { ws.openPanel() }),
         ("Save All", { ws.saveAll() }), ("Close Saved Tabs", { ws.groups.forEach(ws.closeSaved) }),
         ("Toggle Word Wrap", { ws.wrap.toggle() }), ("Toggle Sidebar", { ws.sidebarVisible.toggle() }),
         ("Split Right", { ws.split(.right) }), ("Split Below", { ws.split(.bottom) }),
         ("Format Document", { if let b = ws.active { Task { await ws.format(b) } } }),
         ("Go to Line", { ws.goToLine() }),
         ("Restart Language Server", { ws.restartLanguageServer() }),
         ("Go to Definition", { ws.goToDefinition() }),
         ("Export Markdown as HTML", { ws.exportMarkdown(pdf: false) }),
         ("Export Markdown as PDF", { ws.exportMarkdown(pdf: true) })]
    }
    private var results: [(String, String, () -> Void)] {
        if mode == .files {
            return ws.rankedFiles(query).map { url in
                (url.lastPathComponent, ws.root.map { FileSearch.relativePath(url, root: $0) } ?? url.path, { ws.open(url) })
            }
        }
        return commands.compactMap { name, run in FuzzyMatcher.score(query, in: name).map { (name, run, $0) } }
            .sorted { $0.2 > $1.2 }.map { ($0.0, "", $0.1) }
    }
    var body: some View {
        VStack(spacing: 0) {
            TextField(mode == .files ? "Open a workspace file…" : "Type a command…", text: $query)
                .textFieldStyle(.plain).font(.title3).padding(16).focused($focused)
                .onSubmit { run() }
                .onKeyPress(.downArrow) { selection = min(max(0, results.count - 1), selection + 1); return .handled }
                .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
            Divider()
            ScrollViewReader { proxy in
                List(Array(results.enumerated()), id: \.offset) { i, result in
                    Button { selection = i; run() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.0)
                            if !result.1.isEmpty { Text(result.1).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }.buttonStyle(.plain).listRowBackground(i == selection ? Color.accentColor.opacity(0.15) : Color.clear).id(i)
                }
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
            if results.isEmpty { Text(mode == .files && ws.root == nil ? "Open a workspace folder first." : "No results").foregroundStyle(.secondary).padding() }
        }.frame(width: 600, height: 400)
            .onAppear { focused = true; if mode == .files { ws.refreshIndex() } }
            .onChange(of: query) { selection = 0 }
            .onMoveCommand { direction in
                if direction == .down { selection = min(max(0, results.count - 1), selection + 1) }
                if direction == .up { selection = max(0, selection - 1) }
            }
            .onExitCommand { ws.palette = nil }
    }
    private func run() {
        guard results.indices.contains(selection) else { return }
        let action = results[selection].2
        ws.palette = nil
        DispatchQueue.main.async { action() }
    }
}
