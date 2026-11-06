import AppKit
import AnotaCore
import Observation
import SwiftUI
import Testing
@testable import Anota

private func tabWorkspace() throws -> (Workspace, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (Workspace(store: SessionStore(dir: dir.appendingPathComponent("session"))), dir)
}

@Test func externalOpenDisplaysLatestFileWithoutDuplicatingTabs() throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = ["a.txt", "b.txt", "c.txt"].map { dir.appendingPathComponent($0) }
    for (i, url) in urls.enumerated() { try TextFile(text: "document \(i)").write(to: url) }
    ws.newFile()
    ws.open(urls[0])
    let first = try #require(ws.active)
    let editor = EditorView(buffer: first, wrap: false, reveal: nil) {}
    let coordinator = editor.makeCoordinator()
    let scroll = editor.makeEditor(coordinator: coordinator)
    let view = try #require(scroll.documentView as? CodeTextView)
    for i in [1, 2, 0, 2] {
        ws.open(urls[i])
        let current = try #require(ws.active)
        EditorView(buffer: current, wrap: false, reveal: nil) {}.updateEditor(scroll, coordinator: coordinator)
        #expect(view.string == "document \(i)")
        #expect(view.buffer === current)
        #expect(coordinator.buffer === current)
        #expect(view.textStorage === current.storage)
        #expect(coordinator.undoManager(for: view) === current.undoManager)
    }
    #expect(ws.focusedGroup.tabs.count == 3)
    #expect(first.storage.layoutManagers.isEmpty)
}

@Test func tabReorderPreservesEditorAndSkipsNoOps() throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    for _ in 0..<4 { ws.newFile() }
    let group = ws.focusedGroup, tabs = group.tabs
    let active = try #require(group.active)
    nonisolated(unsafe) var activeChanged = false
    withObservationTracking { _ = group.active } onChange: { activeChanged = true }
    #expect(ws.move(active.id, to: group, before: tabs[0]))
    #expect(group.tabs.first === active)
    #expect(ws.move(active.id, to: group, before: tabs[2], after: true))
    #expect(group.tabs.last === active)
    #expect(!ws.move(active.id, to: group))
    #expect(!ws.move(active.id, to: group, before: active))
    #expect(ws.move(tabs[0].id, to: group, before: active, after: true))
    #expect(group.active === active)
    #expect(!activeChanged)
}

@Test func crossPaneMoveKeepsOneBufferAndDropsEmptyPane() throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    ws.newFile()
    let original = ws.focusedGroup
    let buffer = try #require(ws.active)
    ws.split()
    let target = ws.focusedGroup
    #expect(ws.move(buffer.id, to: target))
    #expect(ws.groups.count == 1)
    #expect(!ws.groups.contains { $0 === original })
    #expect(target.tabs.count == 1)
    #expect(target.active === buffer)
}

@Test func hostedPaneTracksExternalOpensAndKeepsEditorWhileReordering() async throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = ["first.txt", "second.txt", "third.txt"].map { dir.appendingPathComponent($0) }
    for (i, url) in urls.enumerated() { try TextFile(text: "pane document \(i)").write(to: url) }
    ws.open(urls[0])
    let group = ws.focusedGroup
    let host = NSHostingView(rootView: GroupView(ws: ws, group: group))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func editors(_ view: NSView) -> [CodeTextView] {
        (view as? CodeTextView).map { [$0] } ?? view.subviews.flatMap(editors)
    }
    func waitForDocument(_ text: String) async throws {
        for _ in 0..<300 {
            host.layoutSubtreeIfNeeded()
            if editors(host).map(\.string) == [text] { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Hosted editor did not display \(text); got \(editors(host).map(\.string))")
    }
    try await waitForDocument("pane document 0")
    for index in [1, 2, 0, 2] {
        ws.open(urls[index])
        try await waitForDocument("pane document \(index)")
    }
    let editor = try #require(editors(host).first)
    let active = try #require(group.active)
    let start = ContinuousClock.now
    for _ in 0..<100 {
        ws.move(active.id, to: group, before: group.tabs.first)
        ws.move(active.id, to: group)
    }
    print("200 horizontal tab reorders: \(start.duration(to: .now))")
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    #expect(editors(host).first === editor)
    #expect(editor.buffer === active)
    #expect(active.storage.layoutManagers.count == 1)
}

@Test func sharedBufferReorderUsesDraggedPane() throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    ws.newFile()
    let original = ws.focusedGroup
    let shared = try #require(ws.active)
    ws.split()
    let target = ws.focusedGroup
    ws.newFile()
    let active = try #require(ws.active)
    #expect(ws.move(shared.id, to: target, from: target))
    #expect(original.tabs.count == 1)
    #expect(original.active === shared)
    #expect(target.tabs.last === shared)
    #expect(target.active === active)
}

@Test func pointerDraggingReordersBothWaysAndIgnoresOutsideStrip() throws {
    let (ws, dir) = try tabWorkspace()
    defer { try? FileManager.default.removeItem(at: dir) }
    for _ in 0..<3 { ws.newFile() }
    let group = ws.focusedGroup, original = group.tabs
    let active = try #require(group.active)
    func updateFrames() {
        ws.tabStripFrames[group.id] = CGRect(x: 0, y: 0, width: 400, height: 34)
        ws.tabFrames[group.id] = Dictionary(uniqueKeysWithValues: group.tabs.enumerated().map { index, buffer in
            (buffer.id, CGRect(x: index * 100, y: 0, width: 100, height: 34))
        })
    }
    ws.draggingTabID = active.id; ws.draggingGroupID = group.id
    updateFrames()
    ws.dragTab(to: CGPoint(x: 10, y: 17))
    #expect(group.tabs.map(\.id) == [original[2].id, original[0].id, original[1].id])
    updateFrames()
    ws.dragTab(to: CGPoint(x: 290, y: 17))
    #expect(group.tabs.map(\.id) == original.map(\.id))
    updateFrames()
    ws.dragTab(to: CGPoint(x: 10, y: 200))
    #expect(group.tabs.map(\.id) == original.map(\.id))
    #expect(group.active === active)
}
