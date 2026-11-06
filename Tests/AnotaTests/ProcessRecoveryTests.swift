import Foundation
import Testing
import AnotaCore
@testable import Anota

/// Invoked in separate processes by scripts/check-crash-recovery.py; never uses the normal profile.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ANOTA_RECOVERY_PROBE_DIR"] != nil))
func processRecoveryProbe() async throws {
    let environment = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(environment["ANOTA_RECOVERY_PROBE_DIR"]))
    let store = SessionStore(dir: root.appendingPathComponent("session"))
    let ws = Workspace(store: store)
    if environment["ANOTA_RECOVERY_PROBE_MODE"] == "restore" {
        let saved = try #require(store.load())
        let tab = try #require(saved.session.tabs.first)
        let recovered = try #require(ws.allBuffers.first { $0.id == tab.id })
        #expect(recovered.isDirty)
        #expect(recovered.text == saved.texts[tab.id])
        #expect(recovered.text.hasPrefix("continuous edit "))
        return
    }
    ws.newFile()
    let buffer = try #require(ws.active)
    for edit in 0..<600 {
        buffer.replaceAll(with: "continuous edit \(edit)")
        if edit >= 35, store.load()?.texts[buffer.id] != nil {
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: root.appendingPathComponent("ready"), options: .atomic)
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("Crash probe was not killed within 60 seconds")
}
