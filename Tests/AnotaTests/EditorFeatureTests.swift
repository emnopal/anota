import AppKit
import PDFKit
import SwiftUI
import WebKit
import AnotaCore
import Testing
@testable import Anota

@Suite(.serialized) struct EditorFeatureTests {
    private func workspace() -> Workspace {
        Workspace(store: SessionStore(dir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
    }
    @Test func windowIsolationAndPersistedPresentation() throws {
        let store = SessionStore(dir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.dir) }
        let a = Workspace(store: store), b = workspace()
        a.newFile(); b.newFile()
        let buffer = try #require(a.active)
        buffer.language = .markdown; buffer.replaceAll(with: "# Draft")
        buffer.viewMode = .split; buffer.scrollFraction = 0.4; buffer.previewScroll = 200
        a.togglePin(buffer, in: a.focusedGroup)
        #expect(b.active?.text == "")
        #expect(a.saveSession())
        let restored = Workspace(store: store)
        let restoredBuffer = try #require(restored.active)
        #expect(restoredBuffer.id == buffer.id)
        #expect(restoredBuffer.text == "# Draft")
        #expect(restoredBuffer.viewMode == .split)
        #expect(restoredBuffer.scrollFraction == 0.4)
        #expect(restoredBuffer.previewScroll == 200)
        #expect(restoredBuffer.pinned)
    }
    @Test func closeSavedPreservesDirtyAndPinned() throws {
        let ws = workspace()
        ws.newFile(); let pin = try #require(ws.active); ws.togglePin(pin, in: ws.focusedGroup)
        ws.newFile(); let dirty = try #require(ws.active); dirty.replaceAll(with: "draft")
        ws.newFile(); let saved = try #require(ws.active)
        ws.closeSaved(in: ws.focusedGroup)
        #expect(ws.allBuffers.contains(pin)); #expect(ws.allBuffers.contains(dirty)); #expect(!ws.allBuffers.contains(saved))
    }
    @Test func multipleSelectionsTypeAndUndo() throws {
        let buffer = Buffer(url: nil, text: "one one")
        let coordinator = EditorView.Coordinator(buffer: buffer)
        let scroll = EditorView(buffer: buffer, wrap: false, reveal: nil) {}.makeEditor(coordinator: coordinator)
        let tv = try #require(scroll.documentView as? CodeTextView)
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        tv.selectNextOccurrence(nil)
        #expect(tv.selectedRanges.count == 2)
        for character in ["t", "w", "o"] {
            tv.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(tv.selectedRanges.count == 2)
        }
        #expect(buffer.text == "two two")
        while buffer.undoManager.canUndo { buffer.undoManager.undo() }
        #expect(buffer.text == "one one")
    }
    @Test func liveRefreshAndRename() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "original.txt")
        try Data("before".utf8).write(to: url)
        let ws = workspace()
        ws.open(url)
        let b = try #require(ws.active)
        try Data("after".utf8).write(to: url, options: .atomic)
        for _ in 0..<40 {
            if b.text == "after" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(b.text == "after")
        ws.renameText = "renamed.txt"; ws.renameItem(url)
        #expect(b.url?.lastPathComponent == "renamed.txt")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: directory.appending(path: "renamed.txt"), encoding: .utf8) == "after")
    }
    @Test func createRenameAndTrashOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ws = workspace(); ws.root = directory
        ws.presentAlert = { alert in Issue.record("\(alert.messageText): \(alert.informativeText)"); return .alertFirstButtonReturn }
        ws.treeFilter = "unmatched"
        ws.createItem(in: directory, folder: true)
        let folder = try #require(ws.renaming)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(ws.treeFilter.isEmpty)
        ws.createItem(in: folder, folder: false)
        let file = try #require(ws.renaming)
        ws.open(file)
        let buffer = try #require(ws.active)
        buffer.replaceAll(with: "recoverable test data")
        ws.trashItem(file)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(ws.save(buffer))
        ws.renameText = "anota-verification-" + UUID().uuidString + ".txt"
        ws.renameItem(file)
        let renamed = try #require(buffer.url)
        #expect(renamed != file)
        let recoverable = try #require(ws.trashItem(renamed))
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
        #expect(!ws.allBuffers.contains(buffer))
        #expect(try String(contentsOf: recoverable, encoding: .utf8) == "recoverable test data")
        // Restore the disposable file out of Trash before normal temporary-directory cleanup.
        try FileManager.default.moveItem(at: recoverable, to: renamed)
    }
    @Test func reopenEncodingPreservesDirtyOnCancel() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "legacy.txt")
        try Data([0x80, 0x0D, 0x0A]).write(to: url)
        let ws = workspace(); ws.open(url)
        let b = try #require(ws.active)
        ws.reopen(b, encoding: .windowsCP1252)
        #expect(b.text == "€\n")
        #expect(b.lineEnding == .crlf)
        try Data([0x80, 0x80, 0x0D, 0x0A]).write(to: url)
        try b.reload()
        #expect(b.text == "€€\n")
        b.replaceAll(with: "unsaved")
        ws.presentAlert = { _ in .alertFirstButtonReturn }
        ws.reopen(b, encoding: .isoLatin1)
        #expect(b.text == "unsaved")
        #expect(b.isDirty)
    }
    @Test func languageServerProtocolEndToEnd() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appending(path: "server.py")
        let source = #"""
        import sys,json
        def send(message):
            body=json.dumps(dict(jsonrpc="2.0",**message)).encode()
            sys.stdout.buffer.write(("Content-Length: %d\r\n\r\n" % len(body)).encode()+body)
            sys.stdout.buffer.flush()
        while True:
            headers={}
            while True:
                line=sys.stdin.buffer.readline()
                if not line: sys.exit()
                if line==b"\r\n": break
                k,v=line.decode().split(":",1); headers[k.lower()]=v.strip()
            m=json.loads(sys.stdin.buffer.read(int(headers['content-length'])))
            method=m.get('method')
            if method=='initialize': send(dict(id=m['id'],result=dict(capabilities={})))
            elif method=='textDocument/didOpen':
                uri=m['params']['textDocument']['uri']
                send(dict(method='textDocument/publishDiagnostics',params=dict(uri=uri,diagnostics=[dict(range=dict(start=dict(line=0,character=0),end=dict(line=0,character=3)),message='test diagnostic',severity=1)])))
            elif method=='textDocument/completion': send(dict(id=m['id'],result=[dict(label='print',insertText='print')]))
            elif method=='textDocument/definition': send(dict(id=m['id'],result=dict(uri=uri,range=dict(start=dict(line=0,character=4),end=dict(line=0,character=7)))))
        """#
        try source.write(to: script, atomically: true, encoding: .utf8)
        let file = directory.appending(path: "source.swift")
        try Data("let foo = 1".utf8).write(to: file)
        let ws = workspace(); ws.open(file)
        let b = try #require(ws.active)
        let coordinator = EditorView.Coordinator(buffer: b)
        let scroll = EditorView(buffer: b, wrap: false, reveal: nil) {}.makeEditor(coordinator: coordinator)
        let tv = try #require(scroll.documentView as? CodeTextView)
        let server = LanguageServer(workspace: ws)
        defer { server.stop() }
        let quoted = "'" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        server.start(command: "python3 " + quoted)
        for _ in 0..<50 {
            if server.ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(server.ready)
        var completed = false
        server.complete(b, offset: 3) { completed = true }
        for _ in 0..<50 {
            if completed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(completed)
        #expect(server.completionWords == ["print"])
        #expect(tv.layoutManager?.temporaryAttribute(.toolTip, atCharacterIndex: 0, effectiveRange: nil) as? String == "test diagnostic")
        server.definition(b)
        for _ in 0..<30 {
            if b.reveal != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(b.reveal?.location == 4)
    }
    @Test func restoringScrollKeepsHorizontalRulerBaseline() throws {
        let buffer = Buffer(url: nil, text: "Beginning of line\nSecond line")
        let coordinator = EditorView.Coordinator(buffer: buffer)
        let scroll = EditorView(buffer: buffer, wrap: false, reveal: nil) {}.makeEditor(coordinator: coordinator)
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scroll.layoutSubtreeIfNeeded()
        let tv = try #require(scroll.documentView as? CodeTextView)
        let origin = scroll.contentView.bounds.minX
        tv.restoreScroll()
        #expect(scroll.contentView.bounds.minX == origin)
    }
    @Test func hostedMarkdownPreviewLoads() async throws {
        let buffer = Buffer(url: URL(filePath: "/tmp/hosted-preview.md"), text: "# Hosted preview\n" + String(repeating: "\nParagraph of preview text.\n", count: 100))
        buffer.viewMode = .split
        struct PreviewHost: View {
            let buffer: Buffer
            var body: some View { MarkdownPreview(buffer: buffer, revision: buffer.revision) }
        }
        let host = NSHostingView(rootView: PreviewHost(buffer: buffer))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func web(in view: NSView) -> WKWebView? { (view as? WKWebView) ?? view.subviews.lazy.compactMap { web(in: $0) }.first }
        var loaded = false
        for _ in 0..<100 {
            if let view = web(in: host), view.url != nil, !view.isLoading { loaded = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(loaded)
        let view = try #require(web(in: host))
        buffer.syncScroll = 0.6
        try await Task.sleep(for: .milliseconds(300))
        let y: Double? = await withCheckedContinuation { continuation in
            view.evaluateJavaScript("window.scrollY", in: nil, in: .defaultClient) { result in
                continuation.resume(returning: (try? result.get()) as? Double)
            }
        }
        #expect((y ?? 0) > 100)
        view.evaluateJavaScript("window.scrollTo(0, 100)", in: nil, in: .defaultClient)
        try await Task.sleep(for: .milliseconds(200))
        #expect(buffer.syncScroll < 0.2)
        #expect(buffer.previewScroll > 0)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANOTA_REAL_LSP"] == "1"))
    func sourceKitCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources/Example"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "// swift-tools-version: 6.2\nimport PackageDescription\nlet package = Package(name: \"Example\", targets: [.target(name: \"Example\")])".write(to: root.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        let file = root.appending(path: "Sources/Example/main.swift")
        try "struct Greeter { func greet() {} }\nlet greeter = Greeter()\ngreeter.".write(to: file, atomically: true, encoding: .utf8)
        let ws = workspace(); ws.root = root; ws.open(file)
        let b = try #require(ws.active)
        let server = LanguageServer(workspace: ws)
        defer { server.stop() }
        server.start(command: "/usr/bin/xcrun sourcekit-lsp")
        for _ in 0..<100 {
            if server.ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(server.ready)
        var completed = false
        server.complete(b, offset: b.storage.length) { completed = true }
        for _ in 0..<180 {
            if completed { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(completed)
        #expect(server.completionWords.contains { $0.contains("greet") })
    }
    @Test func markdownPDFExport() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let exporter = MarkdownExporter()
        var finished = false
        var exportError: Error?
        exporter.export(MarkdownHTML.page("# Export test\n\n- [x] rendered\n\n```swift\nlet n = 42\n```"), base: nil, to: url) { error in
            exportError = error; finished = true
        }
        for _ in 0..<100 {
            if finished { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(finished)
        #expect(exportError == nil)
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount >= 1)
        #expect(document.string?.contains("Export test") == true)
    }
    @Test func largeLogAndJSON() async throws {
        let text = String(repeating: "2026-11-06 INFO request completed\n", count: 320_000)
        #expect(text.utf8.count >= 10_000_000)
        let buffer = Buffer(url: URL(filePath: "/tmp/performance.log"), text: text)
        #expect(buffer.lines.lineCount == 320_001)
        buffer.replace(NSRange(location: buffer.storage.length, length: 0), with: "end")
        #expect(buffer.text.hasSuffix("end"))
        let json = "[" + (0..<50_000).map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        let parsed = await TreeViewer.parse(text: json, language: .json, plist: false)
        guard case .success(let tree) = parsed else { Issue.record("50K-node JSON failed"); return }
        #expect(tree.children?.count == 50_000)
    }
}
