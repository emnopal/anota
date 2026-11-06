import AppKit
import Foundation
import Testing
import AnotaCore
@testable import Anota

@Test func recoveryWhileContinuouslyEditing() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = SessionStore(dir: dir)
    let ws = Workspace(store: store)
    ws.newFile()
    let buffer = try #require(ws.active)
    for i in 0..<12 {
        buffer.replaceAll(with: "edit \(i)")
        try await Task.sleep(for: .milliseconds(200))
    }
    let recovered = try #require(store.load())
    #expect(recovered.texts[buffer.id] != nil)
    #expect(recovered.texts[buffer.id] != "edit 0")
    #expect(ws.saveSession())
    #expect(store.load()?.texts[buffer.id] == buffer.text)
}

@Test func recoveryWriteFailureIsReported() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("blocked".utf8).write(to: dir)
    defer { try? FileManager.default.removeItem(at: dir) }
    let ws = Workspace(store: SessionStore(dir: dir))
    ws.newFile()
    ws.active?.replaceAll(with: "keep me")
    #expect(!ws.saveSession())
    #expect(ws.active?.text == "keep me")
    #expect(ws.statusMessage?.contains("Recovery save failed") == true)
}

@Test func dataReloadClearsQueryResults() async {
    let buffer = Buffer(url: URL(fileURLWithPath: "/tmp/test.csv"), text: "name\nold\n")
    let model = DataModel()
    await model.load(buffer)
    model.result = DataTable(columns: ["stale"], rows: [["old result"]])
    buffer.replaceAll(with: "name\nnew\n")
    await model.load(buffer)
    #expect(model.result == nil)
    #expect(model.shown?.rows == [["new"]])
}

@Test func gridPublishesSortedOrder() async throws {
    let coordinator = DataGrid.Coordinator()
    let table = GridTableView()
    coordinator.tableView = table
    var ordered: [Int] = []
    coordinator.ordered = { ordered = $0 ?? [] }
    coordinator.update(table: DataTable(columns: ["name"], rows: [["Gamma"], ["Alpha"], ["Beta"]]), version: 1, filter: "", column: nil)
    table.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
    coordinator.tableView(table, sortDescriptorsDidChange: [])
    for _ in 0..<500 {
        if ordered == [1, 2, 0] { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(ordered == [1, 2, 0])
}

@Test func supersededDataLoadCannotReplaceNewerData() async {
    let buffer = Buffer(url: URL(fileURLWithPath: "/tmp/revision.csv"), text: "name\n" + String(repeating: "old\n", count: 100_000))
    let model = DataModel()
    let oldLoad = Task { await model.load(buffer) }
    await Task.yield()
    buffer.replaceAll(with: "name\nlatest\n")
    await model.load(buffer)
    await oldLoad.value
    #expect(model.shown?.rows == [["latest"]])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ANOTA_BENCHMARK"] == "1"))
func largeGridBenchmark() async {
    let table = DataTable(columns: ["name", "description"], rows: (0..<100_000).map { ["row\($0)", "some searchable text"] })
    let timings = await Task.detached {
        (0..<20).map { _ -> Double in
            let start = ContinuousClock.now
            let matches = table.matching("searchable")
            precondition(matches.count == 100_000)
            let elapsed = start.duration(to: .now).components
            return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        }.sorted()
    }.value
    print("100K row filter compute: p50=\(timings[9])ms p95=\(timings[18])ms")
}
