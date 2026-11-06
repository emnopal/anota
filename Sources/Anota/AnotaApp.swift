import AnotaCore
import AppKit
import SwiftUI

@main
struct AnotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Anota", id: "workspace", for: String.self) { $id in
            WorkspaceWindow(restoredID: id)
        }.restorationBehavior(.disabled)
        .commands { WindowCommands() }
        Settings { SettingsView() }
    }
}

private struct WorkspaceKey: FocusedValueKey { typealias Value = Workspace }
extension FocusedValues {
    var workspace: Workspace? {
        get { self[WorkspaceKey.self] }
        set { self[WorkspaceKey.self] = newValue }
    }
}

final class WindowWorkspaces {
    static let shared = WindowWorkspaces()
    var workspaces: [String: Workspace] = [:]
    private var recoveryIDs = Set<String>()
    private var unclaimedRestoreIDs = Set<String>()
    var quitting = false
    var restored = false
    var pendingNewFile = false
    var pendingOpen = false
    let restoreIDs = UserDefaults.standard.stringArray(forKey: "workspaceWindows") ?? []
    init() { unclaimedRestoreIDs = Set(restoreIDs) }
    func newID() -> String {
        if workspaces.isEmpty { return (!restored ? restoreIDs.first : recoveryIDs.first) ?? UUID().uuidString }
        return UUID().uuidString
    }
    func persistWindows() { UserDefaults.standard.set(Set(workspaces.keys).union(recoveryIDs).union(unclaimedRestoreIDs).sorted(), forKey: "workspaceWindows") }
    func close(_ id: String) {
        guard !quitting else { return }
        if workspaces[id]?.allBuffers.contains(where: \.isDirty) == true { recoveryIDs.insert(id) }
        else { recoveryIDs.remove(id) }
        workspaces[id]?.languageServer?.stop()
        workspaces.removeValue(forKey: id)
        persistWindows()
    }
    func workspace(_ id: String) -> Workspace {
        if let ws = workspaces[id] { return ws }
        let store = SessionStore(dir: SessionStore.standard.dir.appending(path: "windows/" + id))
        if !UserDefaults.standard.bool(forKey: "migratedWindowSessions"), let (session, texts) = SessionStore.standard.load() {
            do {
                try store.save(session, changed: texts)
                UserDefaults.standard.set(true, forKey: "migratedWindowSessions")
            } catch { return Workspace.shared }
        }
        let ws = Workspace(store: store)
        recoveryIDs.remove(id)
        unclaimedRestoreIDs.remove(id)
        workspaces[id] = ws
        persistWindows()
        return ws
    }
}

struct WorkspaceWindow: View {
    let restoredID: String?
    @SceneStorage("workspaceID") private var sceneID = WindowWorkspaces.shared.newID()
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let id = restoredID ?? sceneID
        let registry = WindowWorkspaces.shared
        let ws = registry.workspace(id)
        ContentView(ws: ws)
            .frame(minWidth: 720, minHeight: 420)
            .focusedSceneValue(\.workspace, ws)
            // Reuse the most recently active scene for Finder/Open With events.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .onOpenURL { ws.open($0) }
            .task {
                if registry.pendingNewFile { registry.pendingNewFile = false; ws.newFile() }
                if registry.pendingOpen { registry.pendingOpen = false; DispatchQueue.main.async { ws.openPanel() } }
                if !registry.restored {
                    registry.restored = true
                    for other in registry.restoreIDs where other != id { openWindow(id: "workspace", value: other) }
                }
            }
            .onDisappear {
                if ws.saveSession() { registry.close(id) }
            }

    }
}

struct WindowCommands: Commands {
    @FocusedValue(\.workspace) var focused
    @Environment(\.openWindow) var openWindow
    var body: some Commands {
        if let focused { AppCommands(ws: focused) }
        else {
            CommandGroup(replacing: .newItem) {
                Button("New File") {
                    WindowWorkspaces.shared.pendingNewFile = true
                    openWindow(id: "workspace")
                }.keyboardShortcut("n")
                Button("Open…") {
                    WindowWorkspaces.shared.pendingOpen = true
                    openWindow(id: "workspace")
                }.keyboardShortcut("o")
            }
        }
        CommandGroup(after: .newItem) {
            Button("New Window") { openWindow(id: "workspace") }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspace: Workspace?
    var presentAlert: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)  // needed when launched as a bare SwiftPM binary
        NSApp.activate()
        Task.detached { _ = CodeFormatter.loginShellPath }  // runs the login shell once, off the main thread
    }

    /// Persist recovery data before quitting; keep the app open if it fails.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let workspaces = workspace.map { [$0] } ?? (WindowWorkspaces.shared.workspaces.isEmpty ? [Workspace.shared] : Array(WindowWorkspaces.shared.workspaces.values))
        for ws in workspaces {
            while !ws.saveSession() {
                let alert = NSAlert()
                alert.messageText = "Couldn't save recovery data"
                alert.informativeText = "Anota will stay open unless recovery succeeds. Free disk space and retry, or save your unsaved documents elsewhere."
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Save As…")
                alert.addButton(withTitle: "Cancel Quit")
                switch presentAlert(alert) {
                case .alertFirstButtonReturn: continue
                case .alertSecondButtonReturn:
                    for buffer in ws.allBuffers where buffer.isDirty {
                        guard ws.saveAs(buffer) else { return .terminateCancel }
                    }
                    if !ws.saveSession() { return .terminateCancel }
                    break
                default: return .terminateCancel
                }
            }
        }
        WindowWorkspaces.shared.quitting = true
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }


}

struct AppCommands: Commands {
    let ws: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { ws.newFile() }.keyboardShortcut("n")
            Menu("Open Recent") {
                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                    Button(url.path) { ws.open(url) }
                }
                Divider()
                Button("Clear Menu") { NSDocumentController.shared.clearRecentDocuments(nil) }
            }
            Button("Quick Open…") { ws.palette = .files }.keyboardShortcut("p")
            Button("Command Palette…") { ws.palette = .commands }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Open…") { ws.openPanel() }.keyboardShortcut("o")
            Divider()
            Button("Reopen Closed Tab") { ws.reopenClosed() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Close Tab") { ws.closeActive() }.keyboardShortcut("w")
            Button("Close Saved") { ws.groups.forEach(ws.closeSaved) }
            Button("Close All Tabs") { ws.groups.forEach(ws.closeAll) }.keyboardShortcut("w", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { if let b = ws.active { ws.saveCommand(b) } }.keyboardShortcut("s")
            Button("Save As…") { if let b = ws.active { ws.saveAs(b) } }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Export Markdown as HTML…") { ws.exportMarkdown(pdf: false) }.disabled(ws.active?.language != .markdown)
            Button("Export Markdown as PDF…") { ws.exportMarkdown(pdf: true) }.disabled(ws.active?.language != .markdown)
            Button("Save All") { ws.saveAll() }.keyboardShortcut("s", modifiers: [.command, .option])
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { ws.find.open(replace: false, buffer: ws.active) }.keyboardShortcut("f")
            Button("Find and Replace…") { ws.find.open(replace: true, buffer: ws.active) }.keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next") { ws.find.step(true) }.keyboardShortcut("g")
            Button("Find Previous") { ws.find.step(false) }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Use Selection for Find") { ws.find.useSelection(ws.active) }.keyboardShortcut("e")
            Button("Find in Files…") {
                ws.sidebarVisible = true
                ws.sidebarMode = .search
                ws.projectSearch.focusToken += 1
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Format Document") {
                if let b = ws.active { Task { await ws.format(b) } }
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])
            Button("Format Selection") {
                if let b = ws.active { Task { await ws.format(b, selection: true) } }
            }
            .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            Toggle("Format on Save", isOn: Binding(get: { ws.formatOnSave }, set: { ws.formatOnSave = $0 }))
            Button("Minify JSON") { ws.minifyJSON() }
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") { ws.sidebarVisible.toggle() }.keyboardShortcut("b", modifiers: [.command, .control])
            Button("Show Explorer") { ws.sidebarVisible = true; ws.sidebarMode = .files }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Toggle("Vertical Tabs", isOn: Binding(get: { ws.verticalTabs }, set: { ws.verticalTabs = $0 }))
                .keyboardShortcut("t", modifiers: [.command, .option])
            Toggle("Word Wrap", isOn: Binding(get: { ws.wrap }, set: { ws.wrap = $0 }))
                .keyboardShortcut("z", modifiers: .option)
            Button("Split Editor") { ws.split() }.keyboardShortcut("\\")
            Button("Split Editor Below") { ws.split(.bottom) }.keyboardShortcut("\\", modifiers: [.command, .option])
            Button("Cycle View Mode") {
                guard let b = ws.active, let i = b.modes.firstIndex(of: b.viewMode) else { return }
                b.viewMode = b.modes[(i + 1) % b.modes.count]
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
        }
        // VS Code editing shortcuts. Sent down the responder chain to the focused editor (CodeTextView).
        CommandMenu("Selection") {
            line("Complete", #selector(NSTextView.complete(_:)), " ", .control)
            line("Bold", #selector(CodeTextView.markdownBold(_:)), "b")
            line("Italic", #selector(CodeTextView.markdownItalic(_:)), "i")
            line("Add Cursor Above", #selector(CodeTextView.addCursorAbove(_:)), .upArrow, [.command, .option])
            line("Add Cursor Below", #selector(CodeTextView.addCursorBelow(_:)), .downArrow, [.command, .option])
            line("Toggle Line Comment", #selector(CodeTextView.toggleLineComment(_:)), "/")
            Divider()
            line("Expand Line Selection", #selector(CodeTextView.expandLineSelection(_:)), "l")
            line("Select Next Occurrence", #selector(CodeTextView.selectNextOccurrence(_:)), "d")
            Divider()
            line("Copy Line Up", #selector(CodeTextView.copyLinesUp(_:)), .upArrow, [.option, .shift])
            line("Copy Line Down", #selector(CodeTextView.copyLinesDown(_:)), .downArrow, [.option, .shift])
            line("Move Line Up", #selector(CodeTextView.moveLinesUp(_:)), .upArrow, .option)
            line("Move Line Down", #selector(CodeTextView.moveLinesDown(_:)), .downArrow, .option)
            line("Delete Line", #selector(CodeTextView.deleteLines(_:)), "k", [.command, .shift])
            Divider()
            line("Insert Line Below", #selector(CodeTextView.insertLineBelow(_:)), .return)
            line("Insert Line Above", #selector(CodeTextView.insertLineAbove(_:)), .return, [.command, .shift])
            line("Indent Line", #selector(CodeTextView.indentLines(_:)), "]")
            line("Outdent Line", #selector(CodeTextView.outdentLines(_:)), "[")
        }
        CommandMenu("Go") {
            Button("Go to Definition") { ws.goToDefinition() }
            Divider()
            Button("Go to Line…") { ws.goToLine() }.keyboardShortcut("g", modifiers: .control)
            Divider()
            Button("Next Tab") { ws.cycleTab(1) }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { ws.cycleTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Next Tab ") { ws.cycleTab(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Tab ") { ws.cycleTab(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            ForEach(1...3, id: \.self) { n in
                Button("Focus Editor Group \(n)") { ws.focusGroup(n) }.keyboardShortcut(KeyEquivalent(Character("\(n)")))
            }
        }
    }

    private func line(_ title: String, _ action: Selector, _ key: KeyEquivalent,
                      _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }.keyboardShortcut(key, modifiers: modifiers)
    }
}
