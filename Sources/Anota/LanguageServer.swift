import AppKit
import AnotaCore

final class LanguageServer {
    weak var workspace: Workspace?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var received = Data()
    private var nextID = 0
    private var pending: [Int: ([String: Any]) -> Void] = [:]
    private var opened: [UUID: Int] = [:]
    private(set) var ready = false
    private var generation = UUID()
    private var requestTimeouts: [Int: Task<Void, Never>] = [:]
    var completionWords: [String] = []

    init(workspace: Workspace) { self.workspace = workspace }
    isolated deinit { stop() }
    func start(command override: String? = nil) {
        stop()
        let command = (override ?? EditorSettings.shared.lspCommand).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let p = Process(), stdin = Pipe(), stdout = Pipe()
        p.executableURL = URL(filePath: "/bin/zsh")
        p.arguments = ["-lc", "exec " + command]
        p.currentDirectoryURL = workspace?.root
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
        process = p; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let generation = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                if data.isEmpty { self.stop(); return }
                self.receive(data)
            }
        }
        do {
            try p.run()
            request("initialize", ["processId": ProcessInfo.processInfo.processIdentifier,
                "rootUri": workspace?.root?.absoluteString as Any? ?? NSNull(),
                "capabilities": ["general": ["positionEncodings": ["utf-16"]], "textDocument": ["completion": ["completionItem": ["snippetSupport": false]]]]]) { [weak self] message in
                guard message["error"] == nil else { self?.workspace?.flash("Language server initialization failed"); return }
                self?.ready = true
                self?.send("initialized", [:])
                self?.workspace?.allBuffers.forEach { self?.sync($0) }
            }
        } catch { workspace?.flash("Can't start language server: \(error.localizedDescription)"); stop() }
    }
    func stop() {
        generation = UUID()
        requestTimeouts.values.forEach { $0.cancel() }; requestTimeouts = [:]
        output?.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close(); try? output?.close()
        input = nil; output = nil; process = nil
        ready = false; opened = [:]; pending = [:]; received = Data()
    }
    private func transmit(_ object: [String: Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        do { try input.write(contentsOf: LSPFraming.frame(data)) }
        catch { workspace?.flash("Language server disconnected"); stop() }
    }
    private func send(_ method: String, _ params: [String: Any]) { transmit(["jsonrpc": "2.0", "method": method, "params": params]) }
    private func request(_ method: String, _ params: [String: Any], response: @escaping ([String: Any]) -> Void) {
        nextID += 1; pending[nextID] = response
        let id = nextID
        requestTimeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            self.pending.removeValue(forKey: id)?(["error": ["message": "Language server timed out"]])
            self.requestTimeouts[id] = nil
        }
        transmit(["jsonrpc": "2.0", "id": nextID, "method": method, "params": params])
    }
    private func receive(_ data: Data) {
        received.append(data)
        do {
            while let body = try LSPFraming.take(from: &received) {
                guard let message = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { continue }
                if let id = message["id"] as? Int, message["method"] == nil {
                    requestTimeouts.removeValue(forKey: id)?.cancel()
                    pending.removeValue(forKey: id)?(message)
                }
                else if message["method"] as? String == "textDocument/publishDiagnostics", let params = message["params"] as? [String: Any] { diagnostics(params) }
                else if let id = message["id"], message["method"] != nil {
                    transmit(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not supported"]])
                }
            }
        } catch { workspace?.flash("Invalid language server response"); stop() }
    }
    func sync(_ buffer: Buffer) {
        // shortcut: full-document sync is capped at 2MB; add incremental sync for larger source files.
        guard ready, let url = buffer.url, !buffer.language.isBinaryData, buffer.storage.length < 2_000_000 else { return }
        let doc: [String: Any] = ["uri": url.absoluteString, "version": buffer.revision]
        if opened[buffer.id] == nil {
            var item = doc
            item["languageId"] = buffer.language.rawValue; item["text"] = buffer.text
            send("textDocument/didOpen", ["textDocument": item])
        } else if opened[buffer.id] != buffer.revision {
            send("textDocument/didChange", ["textDocument": doc, "contentChanges": [["text": buffer.text]]])
        }
        opened[buffer.id] = buffer.revision
    }
    private func params(_ b: Buffer, _ offset: Int) -> [String: Any]? {
        guard let url = b.url else { return nil }
        let line = b.lines.line(at: offset)
        return ["textDocument": ["uri": url.absoluteString], "position": ["line": line - 1, "character": offset - b.lines.start(ofLine: line)]]
    }
    func complete(_ b: Buffer, offset: Int, done: @escaping () -> Void) {
        sync(b)
        guard b.storage.length < 2_000_000 else { workspace?.flash("LSP is limited to files under 2 million characters"); return }
        guard ready, let params = params(b, offset) else { workspace?.flash("Configure an LSP server in Settings first."); return }
        let revision = b.revision
        request("textDocument/completion", params) { [weak self, weak b] message in
            guard b?.revision == revision else { return }
            let result = message["result"]
            let items = (result as? [[String: Any]]) ?? (result as? [String: Any])?["items"] as? [[String: Any]] ?? []
            self?.completionWords = items.prefix(200).compactMap { item in
                if item["insertTextFormat"] as? Int == 2 { return item["label"] as? String }
                return (item["textEdit"] as? [String: Any])?["newText"] as? String ?? item["insertText"] as? String ?? item["label"] as? String
            }
            done()
        }
    }
    func closed(_ b: Buffer) {
        guard opened.removeValue(forKey: b.id) != nil, let url = b.url else { return }
        send("textDocument/didClose", ["textDocument": ["uri": url.absoluteString]])
    }

    func definition(_ b: Buffer) {
        sync(b)
        guard b.storage.length < 2_000_000 else { workspace?.flash("LSP is limited to files under 2 million characters"); return }
        guard ready, let params = params(b, b.selection.location) else { workspace?.flash("Configure an LSP server in Settings first."); return }
        request("textDocument/definition", params) { [weak self] message in
            let result = message["result"]
            guard let location = (result as? [[String: Any]])?.first ?? result as? [String: Any],
                  let uri = location["uri"] as? String ?? location["targetUri"] as? String,
                  let url = URL(string: uri), url.isFileURL,
                  let range = location["range"] as? [String: Any] ?? location["targetSelectionRange"] as? [String: Any],
                  let start = range["start"] as? [String: Int] else { self?.workspace?.flash("No definition found"); return }
            self?.workspace?.open(url)
            if let b = self?.workspace?.buffer(for: url) {
                b.viewMode = .text
                b.reveal = NSRange(location: Self.offset(start, b), length: 0)
            }
        }
    }
    private static func offset(_ position: [String: Int], _ b: Buffer) -> Int {
        let line = min(b.lines.lineCount, max(1, (position["line"] ?? 0) + 1))
        let end = line < b.lines.lineCount ? b.lines.start(ofLine: line + 1) - 1 : b.storage.length
        return min(end, b.lines.start(ofLine: line) + max(0, position["character"] ?? 0))
    }
    private func diagnostics(_ params: [String: Any]) {
        guard let uri = params["uri"] as? String, let url = URL(string: uri), let b = workspace?.buffer(for: url),
              let items = params["diagnostics"] as? [[String: Any]] else { return }
        if let version = params["version"] as? Int, version != b.revision { return }
        for lm in b.storage.layoutManagers {
            let all = NSRange(location: 0, length: b.storage.length)
            lm.removeTemporaryAttribute(.toolTip, forCharacterRange: all)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            for item in items {
                guard let range = item["range"] as? [String: [String: Int]], let start = range["start"], let end = range["end"] else { continue }
                let a = Self.offset(start, b), z = Self.offset(end, b)
                guard z > a else { continue }
                let r = NSRange(location: a, length: z - a)
                lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.12), forCharacterRange: r)
                lm.addTemporaryAttribute(.toolTip, value: item["message"] as? String ?? "Diagnostic", forCharacterRange: r)
            }
        }
    }
}

extension Workspace {
    func restartLanguageServer() {
        languageServer?.stop()
        languageServer = LanguageServer(workspace: self)
        languageServer?.start()
    }
    func goToDefinition() { if let b = active { languageServer?.definition(b) } }
}
