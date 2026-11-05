import AnotaCore
import AppKit
import SwiftUI

@main
struct AnotaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let ws = Workspace.shared

    var body: some Scene {
        Window("Anota", id: "main") {
            ContentView(ws: ws)
                .frame(minWidth: 720, minHeight: 420)
        }
        .commands { AppCommands(ws: ws) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)  // needed when launched as a bare SwiftPM binary
        NSApp.activate()
        Task.detached { _ = CodeFormatter.loginShellPath }  // runs the login shell once, off the main thread
    }

    /// Hot exit: never prompt, just persist everything.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Workspace.shared.saveSession()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(Workspace.shared.open)
    }
}

struct AppCommands: Commands {
    let ws: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New File") { ws.newFile() }.keyboardShortcut("n")
            Button("Open…") { ws.openPanel() }.keyboardShortcut("o")
            Divider()
            Button("Reopen Closed Tab") { ws.reopenClosed() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Close Tab") { ws.closeActive() }.keyboardShortcut("w")
            Button("Close All Tabs") { ws.groups.forEach(ws.closeAll) }.keyboardShortcut("w", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { if let b = ws.active { ws.saveCommand(b) } }.keyboardShortcut("s")
            Button("Save As…") { if let b = ws.active { ws.saveAs(b) } }.keyboardShortcut("s", modifiers: [.command, .shift])
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
            Button("Toggle Sidebar") { ws.sidebarVisible.toggle() }.keyboardShortcut("b")
            Button("Show Explorer") { ws.sidebarVisible = true; ws.sidebarMode = .files }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Toggle("Vertical Tabs", isOn: Binding(get: { ws.verticalTabs }, set: { ws.verticalTabs = $0 }))
                .keyboardShortcut("t", modifiers: [.command, .option])
            Toggle("Word Wrap", isOn: Binding(get: { ws.wrap }, set: { ws.wrap = $0 }))
                .keyboardShortcut("z", modifiers: .option)
            Button("Split Editor") { ws.split() }.keyboardShortcut("\\")
            Button("Cycle View Mode") {
                guard let b = ws.active, let i = b.modes.firstIndex(of: b.viewMode) else { return }
                b.viewMode = b.modes[(i + 1) % b.modes.count]
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
        }
        // VS Code editing shortcuts. Sent down the responder chain to the focused editor (CodeTextView).
        CommandMenu("Selection") {
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
