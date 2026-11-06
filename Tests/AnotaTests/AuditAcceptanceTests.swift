import AppKit
import Foundation
import Testing
import WebKit
import AnotaCore
@testable import Anota

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw CocoaError(.coderValueNotFound)
}

private final class ManualCheckpointClock {
    var now: Duration = .zero
    var waiters: [(deadline: Duration, continuation: CheckedContinuation<Void, Never>)] = []
    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { waiters.append((now + duration, $0)) }
    }
    func advance(_ duration: Duration) {
        now += duration
        let due = waiters.filter { $0.deadline <= now }
        waiters.removeAll { $0.deadline <= now }
        due.forEach { $0.continuation.resume() }
    }
}

@Test func deterministicCheckpointDoesNotMoveDuringEdits() async throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = ManualCheckpointClock()
    defer { clock.advance(.seconds(100)) }
    let store = SessionStore(dir: dir)
    let ws = Workspace(store: store, checkpointSleep: { await clock.sleep($0) })
    ws.newFile()
    let buffer = try #require(ws.active)
    try await eventually { !clock.waiters.isEmpty }
    for edit in 0..<15 {
        buffer.replaceAll(with: "continuous edit \(edit)")
        for _ in 0..<5 { await Task.yield() }
        clock.advance(.milliseconds(200))
        for _ in 0..<5 { await Task.yield() }
        if edit % 5 == 4 {
            try await eventually { store.load()?.texts[buffer.id] == buffer.text }
        }
    }
    #expect(ws.saveSession())
}

@Test func quitFailureCancelRetryAndSaveAs() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let blocked = root.appendingPathComponent("session")
    try Data("blocked".utf8).write(to: blocked)
    let ws = Workspace(store: SessionStore(dir: blocked))
    ws.newFile(); ws.active?.replaceAll(with: "unsaved work")
    let delegate = AppDelegate(); delegate.workspace = ws
    delegate.presentAlert = { alert in
        #expect(alert.buttons.map(\.title) == ["Retry", "Save As…", "Cancel Quit"])
        return .alertThirdButtonReturn
    }
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
    #expect(ws.active?.text == "unsaved work")
    let destination = root.appendingPathComponent("saved.txt")
    ws.savePanelURL = { _ in destination }
    delegate.presentAlert = { _ in .alertSecondButtonReturn }
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "unsaved work")
    ws.active?.replaceAll(with: "latest work")
    delegate.presentAlert = { _ in
        try? FileManager.default.removeItem(at: blocked)
        return .alertFirstButtonReturn
    }
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    #expect(SessionStore(dir: blocked).load()?.texts[ws.active!.id] == "latest work")
}

@Test func foregroundReactivationAndSaveAllConflicts() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let ws = Workspace(store: SessionStore(dir: root.appendingPathComponent("session")))
    let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
    try TextFile(text: "original a").write(to: a)
    try TextFile(text: "original b").write(to: b)
    ws.open(a); ws.open(b)
    let first = try #require(ws.buffer(for: a)), second = try #require(ws.buffer(for: b))
    first.replaceAll(with: "mine a"); second.replaceAll(with: "mine b")
    try TextFile(text: "external a").write(to: a)
    var prompts = 0
    ws.presentAlert = { _ in prompts += 1; return .alertFirstButtonReturn }
    #expect(!ws.save(first))
    #expect(try TextFile.read(a).text == "external a")
    ws.checkDisk()
    #expect(first.conflict)
    try TextFile(text: "external b").write(to: b)
    ws.saveAll()
    #expect(prompts == 3)
    #expect(try TextFile.read(b).text == "external b")
    ws.presentAlert = { _ in .alertThirdButtonReturn }
    #expect(!ws.save(first)); #expect(first.text == "external a")
    ws.presentAlert = { _ in .alertSecondButtonReturn }
    #expect(ws.save(second)); #expect(try TextFile.read(b).text == "mine b")
}

@Test func rapidSearchChangesAndPreviewToDisk() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("text.txt")
    try TextFile(text: "CAT cat dog").write(to: url)
    let ws = Workspace(store: SessionStore(dir: root.appendingPathComponent("session")))
    ws.root = root
    let search = ProjectSearch()
    search.options.query = "dog"; search.run(root: root)
    search.options.query = "(cat)"; search.options.regex = true; search.options.preserveCase = true
    search.replacement = "$1s"; search.run(root: root)
    #expect(!search.canReplace)
    try await eventually { !search.running }
    #expect(search.canReplace)
    let file = try #require(search.results.first)
    let previews = try file.matches.map { try $0.replacement(in: file.text, options: search.options, template: search.replacement) }
    #expect(previews == ["CATS", "cats"])
    search.options.query = "dog"
    #expect(!search.canReplace)
    search.options.query = "(cat)"
    search.confirmReplacement = { _ in .alertFirstButtonReturn }
    search.replaceAll(in: ws)
    #expect(try TextFile.read(url).text == "CATS cats dog")
    try await eventually { !search.running }
    search.replacement = ""
    search.replaceAll(in: ws)
    #expect(try TextFile.read(url).text == "S s dog")
}

@Test func sortedFilteredExportAndClipboardMatchGrid() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = Buffer(url: root.appendingPathComponent("table.csv"), text: "name\nGamma\nAlpha\nBeta\n")
    let model = DataModel(); await model.load(source)
    let coordinator = DataGrid.Coordinator(), table = GridTableView()
    coordinator.tableView = table
    model.filter = "a"
    let shown = try #require(model.shown), version = model.version
    coordinator.ordered = { model.acceptDisplayed($0, table: shown, version: version, filter: model.filter, column: nil) }
    coordinator.update(table: try #require(model.shown), version: model.version, filter: "a", column: nil)
    table.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
    coordinator.tableView(table, sortDescriptorsDidChange: [])
    try await eventually { model.displayedRows == [1, 2, 0] }
    let csv = root.appendingPathComponent("sorted.csv"), json = root.appendingPathComponent("sorted.json")
    try model.export(.csv, to: csv); try model.export(.json, to: json)
    #expect(try String(contentsOf: csv, encoding: .utf8) == "name\nAlpha\nBeta\nGamma\n")
    let objects = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as! [[String: String]]
    #expect(objects.compactMap { $0["name"] } == ["Alpha", "Beta", "Gamma"])
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    model.copyAll(to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "name\nAlpha\nBeta\nGamma")
    model.filter = "Al"
    #expect(!model.canExport)
    #expect(throws: CocoaError.self) { try model.export(.csv, to: csv) }
    #expect(try String(contentsOf: csv, encoding: .utf8) == "name\nAlpha\nBeta\nGamma\n")
    coordinator.update(table: try #require(model.shown), version: model.version, filter: "Al", column: nil)
    try await eventually { model.displayedRows == [1] }
    try model.export(.csv, to: csv); model.copyAll(to: pasteboard)
    #expect(try String(contentsOf: csv, encoding: .utf8) == "name\nAlpha\n")
    #expect(pasteboard.string(forType: .string) == "name\nAlpha")
}

@Test func nativeMarkdownBlocksActiveContentAndKeepsScroll() async throws {
    let coordinator = MarkdownPreview.Coordinator()
    let web = MarkdownPreview.makeWebView(coordinator: coordinator)
    #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    let buffer = Buffer(url: URL(fileURLWithPath: "/tmp/preview.md"), text: """
    # Safe heading
    <script>document.title='EXECUTED'</script>
    <img src=x onerror="document.title='EXECUTED'">
    <meta http-equiv="refresh" content="0;url=https://example.invalid">
    [bad](javascript:alert(1))
    ```html
    <b>& literal</b>
    ```
    """ + String(repeating: "\n\nparagraph", count: 200))
    web.setFrameSize(NSSize(width: 600, height: 400))
    MarkdownPreview(buffer: buffer, revision: buffer.revision).update(web, coordinator: coordinator)
    try await eventually { !web.isLoading && web.url != nil }
    let text = try await javaScript(web, "document.body.innerText")
    #expect(text.contains("Safe heading") == true)
    #expect(text.contains("<b>& literal</b>") == true)
    let active = try await javaScript(web, "document.querySelectorAll('script,meta[http-equiv=refresh],[onerror],a[href^=javascript]').length")
    #expect(active == "0")
    _ = try await javaScript(web, "window.scrollTo(0, 300)")
    buffer.replaceAll(with: buffer.text + "\n\nmore")
    MarkdownPreview(buffer: buffer, revision: buffer.revision).update(web, coordinator: coordinator)
    try await Task.sleep(for: .milliseconds(500))
    let y = try await javaScript(web, "window.scrollY")
    #expect((Double(y) ?? 0) >= 290)
    #expect(web.url?.host != "example.invalid")
    let original = web.url
    web.load(URLRequest(url: URL(string: "https://example.invalid/unsolicited")!))
    try await Task.sleep(for: .milliseconds(200))
    #expect(web.url == original)
    coordinator.pendingLoad = true
    web.loadHTMLString("<title>fixed</title><script>document.title='EXECUTED'</script><p id='ready'>ready</p>", baseURL: nil)
    for _ in 0..<100 {
        if (try? await javaScript(web, "document.getElementById('ready') !== null")) == "true" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(try await javaScript(web, "document.title") == "fixed")
}

private func javaScript(_ web: WKWebView, _ expression: String) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        web.evaluateJavaScript("String(" + expression + ")", in: nil, in: .defaultClient) { result in
            do { continuation.resume(returning: try result.get() as? String ?? "") }
            catch { continuation.resume(throwing: error) }
        }
    }
}

@Test func largeGridAndTreeLeaveMainActorResponsive() async throws {
    let coordinator = DataGrid.Coordinator(), grid = GridTableView()
    coordinator.tableView = grid
    var computed = false
    coordinator.ordered = { if $0?.count == 100_000 { computed = true } }
    let table = DataTable(columns: ["name", "description"], rows: (0..<100_000).map { ["row\($0)", "searchable"] })
    let json = "[" + (0..<30_000).map { "{\"value\":\($0)}" }.joined(separator: ",") + "]"
    var gaps: [Double] = [], last = ContinuousClock.now
    let heartbeat = Task {
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(10))
            let now = ContinuousClock.now
            let elapsed = last.duration(to: now).components
            gaps.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            last = now
        }
    }
    coordinator.update(table: table, version: 1, filter: "searchable", column: nil)
    let tree = await TreeViewer.parse(text: json, language: .json, plist: false)
    if case .failure(let error) = tree { Issue.record("\(error)") }
    try await eventually { computed }
    try await heartbeat.value
    let sorted = gaps.sorted()
    print("Main actor heartbeat during 100K-row grid + 30K-object tree: p50=\(sorted[49])ms p95=\(sorted[94])ms max=\(sorted.last!)ms")
    #expect(sorted[94] < 250)
}
