import AppKit
import AnotaCore
import Testing
import SwiftUI
@testable import Anota

private func splitWorkspace() throws -> (Workspace, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (Workspace(store: SessionStore(dir: directory)), directory)
}

@Test(arguments: SplitDirection.allCases)
func workspaceSplitsEveryDirection(_ direction: SplitDirection) throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile(); ws.active?.replaceAll(with: "unsaved")
    let original = ws.focusedGroup, buffer = try #require(ws.active)
    ws.split(direction)
    #expect(ws.groups.count == 2)
    #expect(ws.active === buffer)
    #expect(original.active === buffer)
    #expect(ws.paneLayout.leaves == (direction.before ? [ws.focusedGroup.id, original.id] : [original.id, ws.focusedGroup.id]))
    #expect(buffer.text == "unsaved")
}

@Test func mixedLayoutAndSizesSurviveSessionRestore() throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile(); ws.active?.replaceAll(with: "recover this")
    ws.split(.right)
    ws.split(.bottom)
    guard case .split(let id, _, _, _, _) = ws.paneLayout else { Issue.record("Missing split"); return }
    ws.resizeSplit(id, ratio: 0.65)
    let expected = ws.paneLayout
    #expect(ws.saveSession())
    let restored = Workspace(store: SessionStore(dir: directory))
    #expect(restored.paneLayout == expected)
    #expect(restored.active?.text == "recover this")
    #expect(restored.groups.count == 3)
    #expect(restored.allBuffers.count == 1)
}

@Test(arguments: SplitDirection.allCases)
func edgeDragCommitsSplitOnlyOnRelease(_ direction: SplitDirection) throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile(); let original = try #require(ws.active)
    ws.newFile(); let moving = try #require(ws.active)
    moving.replaceAll(with: "dragged edits")
    let source = ws.focusedGroup
    ws.paneFrames[source.id] = CGRect(x: 100, y: 100, width: 600, height: 400)
    let point: CGPoint
    switch direction {
    case .left: point = CGPoint(x: 110, y: 300)
    case .right: point = CGPoint(x: 690, y: 300)
    case .top: point = CGPoint(x: 400, y: 110)
    case .bottom: point = CGPoint(x: 400, y: 490)
    }
    ws.draggingTabID = moving.id; ws.draggingGroupID = source.id
    ws.dragTab(to: point)
    #expect(ws.splitDrop?.direction == direction)
    #expect(ws.groups.count == 1)
    ws.finishTabDrag()
    #expect(ws.groups.count == 2)
    #expect(source.active === original)
    #expect(ws.active === moving)
    #expect(ws.active?.text == "dragged edits")
    #expect(ws.splitDrop == nil)
    #expect(ws.draggingTabID == nil)
}

@Test func loneTabEdgeSplitKeepsOriginalPaneAndSharesBuffer() throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile()
    let source = ws.focusedGroup, buffer = try #require(ws.active)
    ws.split(.bottom, in: source, moving: buffer.id, from: source)
    #expect(ws.groups.count == 2)
    #expect(source.active === buffer)
    #expect(ws.active === buffer)
    ws.dropIfEmpty(source)
    #expect(ws.groups.count == 2)
}

@Test func hostedMixedSplitsMeasureDropZonesAndResizeBothAxes() async throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile()
    let left = ws.focusedGroup.id
    ws.split(.right)
    let top = ws.focusedGroup.id
    ws.split(.bottom)
    let bottom = ws.focusedGroup.id
    let host = NSHostingView(rootView: PaneLayoutView(ws: ws, node: ws.paneLayout))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    try await settle()
    let a = try #require(ws.paneFrames[left])
    let b = try #require(ws.paneFrames[top])
    let c = try #require(ws.paneFrames[bottom])
    #expect(a.width > 400 && a.height > 600)
    #expect(b.minX > a.minX && c.minX == b.minX)
    #expect(c.minY > b.maxY)
    guard case .split(let x, _, _, _, .split(let y, _, _, _, _)) = ws.paneLayout else {
        Issue.record("Missing mixed layout"); return
    }
    ws.resizeSplit(x, ratio: 0.6)
    ws.resizeSplit(y, ratio: 0.6)
    host.rootView = PaneLayoutView(ws: ws, node: ws.paneLayout)
    try await settle()
    #expect(try #require(ws.paneFrames[left]).width > a.width + 90)
    #expect(try #require(ws.paneFrames[top]).height > b.height + 50)
    let frame = try #require(ws.paneFrames[bottom])
    ws.draggingTabID = ws.active?.id; ws.draggingGroupID = bottom
    ws.dragTab(to: CGPoint(x: frame.midX, y: frame.maxY - 5))
    #expect(ws.splitDrop?.direction == .bottom)
    ws.finishTabDrag()
    #expect(ws.groups.count == 4)
}

@Test(arguments: [true, false])
func crossPaneDragWaitsForReleaseAndCanMoveLastTab(toStrip: Bool) throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile()
    let source = ws.focusedGroup, buffer = try #require(ws.active)
    buffer.replaceAll(with: "keep these edits")
    ws.split(.right)
    let target = ws.focusedGroup
    ws.newFile()
    let neighbor = try #require(ws.active)
    ws.tabStripFrames[target.id] = CGRect(x: 500, y: 0, width: 500, height: 34)
    ws.tabFrames[target.id] = [neighbor.id: CGRect(x: 500, y: 0, width: 120, height: 34)]
    ws.paneFrames[target.id] = CGRect(x: 500, y: 34, width: 500, height: 500)
    ws.draggingTabID = buffer.id; ws.draggingGroupID = source.id
    ws.dragTab(to: toStrip ? CGPoint(x: 510, y: 17) : CGPoint(x: 750, y: 280))
    #expect(ws.groups.count == 2)
    #expect(source.tabs == [buffer])
    #expect(ws.tabDrop?.groupID == target.id)
    ws.finishTabDrag()
    #expect(ws.groups.count == 1)
    #expect(ws.active === buffer)
    #expect(target.tabs.filter { $0 === buffer }.count == 1)
    #expect(buffer.text == "keep these edits")
    #expect(ws.draggingTabID == nil && ws.tabDrop == nil)
    ws.newFile()
    ws.tabFrames[target.id] = [try #require(target.tabs.first).id: CGRect(x: 500, y: 0, width: 120, height: 34)]
    ws.draggingTabID = ws.active?.id; ws.draggingGroupID = target.id
    ws.dragTab(to: CGPoint(x: 510, y: 17))
    #expect(target.tabs.first === ws.active)
    ws.cancelTabDrag()
}

@Test func canceledDragAndClosedPaneClearPendingDestination() throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile()
    let source = ws.focusedGroup, buffer = try #require(ws.active)
    ws.split(.bottom)
    let target = ws.focusedGroup
    ws.draggingTabID = buffer.id; ws.draggingGroupID = source.id
    ws.tabDrop = .init(groupID: target.id, beforeID: nil, after: false)
    ws.cancelTabDrag()
    ws.finishTabDrag()
    #expect(ws.groups.count == 2)
    ws.close(buffer, in: target)
    #expect(ws.groups.count == 1)
    #expect(ws.active === buffer)
    ws.newFile()
    let next = try #require(ws.active)
    ws.move(next.id, to: source, before: buffer)
    #expect(source.tabs == [next, buffer])
}

@Test func directoryFileDropsOpenInTargetOrSplitWithoutLosingOtherTabs() throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appendingPathComponent("first.txt")
    let second = directory.appendingPathComponent("second.txt")
    try "first".write(to: first, atomically: true, encoding: .utf8)
    try "second".write(to: second, atomically: true, encoding: .utf8)
    ws.newFile(); ws.active?.replaceAll(with: "unsaved")
    let original = ws.focusedGroup, dirty = try #require(ws.active)
    ws.split(.right)
    let target = ws.focusedGroup
    ws.focusedID = original.id
    ws.dropFiles([first, second], in: target)
    #expect(ws.focusedGroup === target)
    #expect(ws.active?.url == second)
    #expect(original.active === dirty && dirty.text == "unsaved")
    ws.dropFiles([first], in: target, direction: .bottom)
    #expect(ws.groups.count == 3)
    #expect(ws.active?.url == first)
    #expect(ws.active === target.tabs.first { $0.url == first })
    ws.dropFiles([directory], in: original, direction: .top)
    #expect(ws.groups.count == 3)
}

private struct LivePaneLayout: View {
    let ws: Workspace
    var body: some View { PaneLayoutView(ws: ws, node: ws.paneLayout) }
}

@Test func closingSplitKeepsSurvivingTabGeometryUsable() async throws {
    let (ws, directory) = try splitWorkspace()
    defer { try? FileManager.default.removeItem(at: directory) }
    ws.newFile(); let first = try #require(ws.active)
    ws.newFile(); let second = try #require(ws.active)
    let surviving = ws.focusedGroup
    ws.split(.bottom)
    let removed = ws.focusedGroup
    let host = NSHostingView(rootView: LivePaneLayout(ws: ws))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() async throws {
        for _ in 0..<40 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    try await settle()
    ws.close(second, in: removed)
    try await settle()
    #expect(ws.groups.count == 1)
    let frame = try #require(ws.tabFrames[surviving.id]?[first.id])
    let pane = try #require(ws.paneFrames[surviving.id])
    #expect(frame.width > 40 && pane.height > 500)
    #expect(ws.tabStripFrames[surviving.id]?.contains(CGPoint(x: frame.midX, y: frame.midY)) == true)
    surviving.active = first
    ws.draggingTabID = second.id; ws.draggingGroupID = surviving.id
    ws.dragTab(to: CGPoint(x: frame.minX + 2, y: frame.midY))
    ws.finishTabDrag()
    #expect(surviving.tabs == [second, first])
    #expect(surviving.active === first)
}

@Test func fileDragProviderPreservesURL() async throws {
    let url = URL(filePath: "/tmp/a file #1.md")
    let provider = NSItemProvider(object: url as NSURL)
    let data: Data? = await withCheckedContinuation { continuation in
        provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
            continuation.resume(returning: data)
        }
    }
    #expect(try #require(data).isEmpty == false)
    #expect(URL(dataRepresentation: try #require(data), relativeTo: nil) == url)
}
