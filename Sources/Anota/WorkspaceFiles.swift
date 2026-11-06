import AppKit
import AnotaCore

extension Workspace {
    func watchFiles() {
        let paths = Set(([root].compactMap { $0 } + allBuffers.compactMap { $0.url?.deletingLastPathComponent() }).map(\.path))
        watcherTask?.cancel()
        watcherTask = Task { [weak self] in
            let watcher = await Task.detached {
                FileWatcher(paths: Array(paths)) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.refreshTask?.cancel()
                        self.refreshTask = Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(250))
                            guard !Task.isCancelled, let self else { return }
                            self.checkDisk()
                            self.refreshIndex()
                        }
                    }
                }
            }.value
            guard !Task.isCancelled else { return }
            self?.watcher = watcher
            self?.checkDisk()
            self?.refreshIndex()
        }
        refreshIndex()
    }

    func refreshIndex() {
        indexTask?.cancel()
        guard let root else { fileIndex = []; return }
        indexTask = Task { [weak self] in
            let worker = Task.detached { FileSearch.files(root: root) }
            let files = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, self?.root == root else { return }
            self?.fileIndex = files
        }
    }

    var filteredFiles: [URL] { rankedFiles(treeFilter) }
    func rankedFiles(_ query: String) -> [URL] {
        fileIndex.compactMap { url -> (URL, Int)? in
            let path = root.map { FileSearch.relativePath(url, root: $0) } ?? url.path
            return FuzzyMatcher.score(query, in: path).map { (url, $0) }
        }.sorted { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }.prefix(200).map(\.0)
    }

    func createItem(in directory: URL, folder: Bool) {
        do {
            let base = folder ? "New Folder" : "Untitled.txt"
            var url = directory.appending(path: base), n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = directory.appending(path: "\(folder ? "New Folder" : "Untitled") \(n)\(folder ? "" : ".txt")"); n += 1
            }
            if folder { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try Data().write(to: url, options: .withoutOverwriting) }
            tree?.find(directory)?.expanded = true
            tree?.find(directory)?.load()
            treeFilter = ""
            renaming = url; renameText = url.lastPathComponent
            refreshIndex()
        } catch { alert("Can't create item", error) }
    }

    func renameItem(_ url: URL) {
        let name = renameText
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { flash("Enter a valid file name"); return }
        let destination = url.deletingLastPathComponent().appending(path: name)
        if destination == url { renaming = nil; return }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            for b in allBuffers {
                if b.url == url { b.url = destination }
                else if let path = b.url?.path, path.hasPrefix(url.path + "/") {
                    b.url = URL(filePath: destination.path + path.dropFirst(url.path.count))
                }
            }
            renaming = nil
            tree?.refresh(); watchFiles(); scheduleSave()
            if languageServer != nil { restartLanguageServer() }
        } catch { alert("Can't rename item", error) }
    }

    @discardableResult
    func trashItem(_ url: URL) -> URL? {
        let affected = allBuffers.filter { $0.url == url || $0.url?.path.hasPrefix(url.path + "/") == true }
        if affected.contains(where: \.isDirty) {
            flash("Save or close unsaved files before moving this item to Trash."); return nil
        }
        do {
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            for g in groups { for b in affected where g.tabs.contains(b) { close(b, in: g) } }
            tree?.refresh(); watchFiles()
            return destination as URL?
        } catch { alert("Can't move item to Trash", error); return nil }
    }

    func reopen(_ b: Buffer, encoding: String.Encoding) {
        guard let url = b.url, !b.language.isBinaryData else { return }
        if b.isDirty {
            let alert = NSAlert()
            alert.messageText = "Discard changes and reopen “\(b.name)”?"
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard and Reopen")
            guard presentAlert(alert) == .alertSecondButtonReturn else { return }
        }
        do {
            let data = try Data(contentsOf: url)
            let normalized = try TextFile.decode(data, encoding: encoding)
            b.setText(normalized.text); b.readEncoding = encoding; b.encoding = encoding; b.lineEnding = normalized.lineEnding
            b.isDirty = false; b.conflict = false
            b.diskDate = modificationDate(url); b.diskRevision = FileRevision(contents: data)
            scheduleSave()
        } catch { alert("Can't reopen file", error) }
    }
}
