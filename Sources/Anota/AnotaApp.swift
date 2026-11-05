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
            Button("Close Tab") { ws.closeActive() }.keyboardShortcut("w")
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
            Toggle("Format on Save", isOn: Binding(get: { ws.formatOnSave }, set: { ws.formatOnSave = $0 }))
            Button("Minify JSON") { ws.minifyJSON() }
        }
        CommandGroup(after: .sidebar) {
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
    }
}
