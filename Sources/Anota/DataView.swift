import AnotaCore
import SwiftUI

/// Grid view for CSV / TSV / JSON-lines (text buffers) and SQLite / Excel (binary files), with an optional SQL box.
/// SQLite files are queried directly (read-only); other formats are imported into an in-memory SQLite database
/// the first time you run SQL, one table per file or sheet.
struct DataView: View {
    let ws: Workspace
    let buffer: Buffer
    @State private var model = DataModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                if model.showSchema { SchemaPanel(model: model, language: buffer.language).frame(minWidth: 160, idealWidth: 220, maxWidth: 360) }
                main.frame(minWidth: 300)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: buffer.revision) { model.workspace = ws; await model.load(buffer) }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var main: some View {
        if model.showSQL {
            VSplitView {
                sqlBox.frame(minHeight: 70, idealHeight: 130)
                content.frame(minHeight: 120)
            }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if buffer.language == .jsonl, model.jsonlRaw, model.result == nil {
            RawRecords(text: buffer.text, filter: model.filter, revision: buffer.revision) { line in
                buffer.viewMode = .text
                buffer.reveal = NSRange(location: buffer.lines.start(ofLine: line), length: 0)
            }
        } else {
            grid
        }
    }

    // MARK: Parts

    private var toolbar: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $model.showSchema) { Image(systemName: "sidebar.left") }
                .help(buffer.language == .sqlite ? "Schema: tables, columns, indexes" : "Columns and types")
            sourcePicker
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
            TextField("Filter rows", text: $model.filter).textFieldStyle(.plain).frame(minWidth: 80)
            if let t = model.shown, !t.columns.isEmpty, !(buffer.language == .jsonl && model.jsonlRaw) {
                Picker("Column", selection: $model.filterColumn) {
                    Text("All columns").tag(Int?.none)
                    Divider()
                    ForEach(t.columns.indices, id: \.self) { Text(t.columns[$0]).tag(Int?.some($0)) }
                }
                .labelsHidden().fixedSize().help("Filter in one column")
            }
            Spacer()
            if buffer.language == .jsonl {
                Picker("Show", selection: $model.jsonlRaw) {
                    Text("Table").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented).fixedSize().help("Table of keys, or each record as formatted JSON")
            }
            if [.csv, .tsv, .excel].contains(buffer.language), model.result == nil {
                Toggle("Header row", isOn: Binding(get: { model.shown?.hasHeaderRow ?? false }, set: { _ in model.toggleHeader() }))
                    .toggleStyle(.checkbox).help("Use the first row as column names")
            }
            if model.result != nil {
                Button("Show \(buffer.language == .sqlite ? "Table" : "File")") { model.result = nil }
            }
            Menu {
                Button("Export as CSV…") { model.export(.csv, name: buffer.name) }
                Button("Export as JSON…") { model.export(.json, name: buffer.name) }
                Divider()
                Button("Copy All as TSV") { model.copyAll() }
            } label: { Image(systemName: "square.and.arrow.up") }
                .menuIndicator(.hidden).fixedSize().help("Export the rows shown (filter applies)")
                .disabled(!model.canExport)
            Toggle(isOn: $model.showSQL) { Label("SQL", systemImage: "terminal") }
                .help("Query with SQL (SQLite dialect; ⌘↩ runs)")
        }
        .buttonStyle(.borderless)
        .toggleStyle(.button)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var sourcePicker: some View {
        if model.sources.count > 1 || buffer.language.isBinaryData {
            let binding = Binding(get: { model.selected }, set: { model.select($0) })
            if buffer.language == .excel, model.sources.count <= 6 {
                Picker("Sheet", selection: binding) {
                    ForEach(model.sources.indices, id: \.self) { Text(model.sources[$0].name).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            } else {
                Picker(buffer.language == .excel ? "Sheet" : "Table", selection: binding) {
                    ForEach(model.sources.indices, id: \.self) { i in
                        Label(model.sources[i].name, systemImage: model.sources[i].isView ? "eye" : "tablecells").tag(i)
                    }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var sqlBox: some View {
        VStack(spacing: 0) {
            EditorView(buffer: model.sqlBuffer(for: buffer), wrap: true, reveal: model.sqlBuffer(for: buffer).reveal) {}
            HStack {
                if let e = model.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
                } else {
                    Text(tablesHint).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.running { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() } }
                Menu {
                    if model.history.isEmpty { Text("No queries yet") }
                    ForEach(model.history, id: \.self) { q in
                        Button(q.count > 80 ? String(q.prefix(80)) + "…" : q) { model.setSQL(q) }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .menuIndicator(.hidden).fixedSize().help("Query history")
                Button("Run") { model.run(buffer) }.help("Run (⌘↩ in the SQL box)")
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private var tablesHint: String {
        "Tables: " + model.sources.map { buffer.language == .sqlite ? $0.name : SQLiteDB.tableName(for: $0.name) }.joined(separator: ", ")
    }

    @ViewBuilder private var grid: some View {
        if let t = model.shown {
            let version = model.version, filter = model.filter, column = model.filterColumn
            DataGrid(table: t, version: version, filter: filter, filterColumn: column, ordered: {
                model.acceptDisplayed($0, table: t, version: version, filter: filter, column: column)
            })
        } else if let e = model.loadError {
            ContentUnavailableView("Can't read \(buffer.language.displayName)", systemImage: "exclamationmark.triangle", description: Text(e))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let t = model.shown {
                Text("\(t.rows.count.formatted()) rows × \(t.columns.count) columns").monospacedDigit()
                if let total = model.total, model.result == nil, total > t.rows.count {
                    Text("(first \(t.rows.count.formatted()) of \(total.formatted()))").foregroundStyle(.orange)
                } else if t.truncated {
                    Text("(first \(t.rows.count.formatted()) shown)").foregroundStyle(.orange)
                }
                if model.result != nil { Text("· query result").foregroundStyle(.secondary) }
                if let w = t.warnings.first { Text(w).foregroundStyle(.orange).help(t.warnings.joined(separator: "\n")) }
            }
            Spacer()
            if buffer.language.isBinaryData { Text("Read-only").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: Schema panel

struct SchemaPanel: View {
    let model: DataModel
    let language: Language

    var body: some View {
        List {
            if language == .sqlite {
                ForEach(model.objects) { o in
                    Section {
                        ForEach(o.columns, id: \.name) { c in
                            HStack(spacing: 6) {
                                Image(systemName: c.primaryKey ? "key.fill" : "circle.fill")
                                    .font(.system(size: c.primaryKey ? 10 : 4)).foregroundStyle(c.primaryKey ? .yellow : .secondary)
                                    .frame(width: 12)
                                Text(c.name)
                                Spacer()
                                Text(c.type.isEmpty ? "ANY" : c.type).foregroundStyle(.secondary)
                                if c.notNull { Text("NOT NULL").font(.caption2).foregroundStyle(.tertiary) }
                            }
                        }
                        ForEach(o.indexes, id: \.self) { i in Label(i, systemImage: "list.number").foregroundStyle(.secondary) }
                    } header: {
                        Button { if let i = model.sources.firstIndex(where: { $0.name == o.name }) { model.select(i) } } label: {
                            Label(o.name, systemImage: o.kind == .view ? "eye" : "tablecells")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let t = model.shown {
                let types = t.columnTypes()
                Section("Columns") {
                    ForEach(t.columns.indices, id: \.self) { i in
                        HStack {
                            Text(types[i].glyph).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 24)
                            Text(t.columns[i])
                            Spacer()
                            Text(types[i].rawValue).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .font(.system(size: 12))
    }
}

// MARK: JSON Lines, raw

/// Each JSON Lines record pretty-printed and coloured, lazily (only visible records are formatted).
struct RawRecords: View {
    let text: String
    let filter: String
    let revision: Int
    let showLine: (Int) -> Void
    @State private var lines: [(n: Int, text: String)] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.n) { line in
                    RawRecord(n: line.n, text: line.text)
                        .contextMenu {
                            Button("Show in Text") { showLine(line.n) }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(line.text, forType: .string)
                            }
                        }
                        .onTapGesture(count: 2) { showLine(line.n) }
                    Divider()
                }
            }
        }
        .task(id: revision) {
            let t = text
            lines = await Task.detached {
                t.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                    .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { (n: $0.offset + 1, text: String($0.element)) }
            }.value
        }
    }

    private var shown: [(n: Int, text: String)] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? lines : lines.filter { $0.text.range(of: f, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

private struct RawRecord: View {
    private static let json = Highlighter(.json)  // one parser + compiled query, reused for every record
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").foregroundStyle(.tertiary).frame(minWidth: 36, alignment: .trailing)
            Text(pretty).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var pretty: AttributedString {
        guard let node = try? JSON.parse(text) else {
            var a = AttributedString(text + "    ← invalid JSON")
            a.foregroundColor = .red
            return a
        }
        let s = JSON.format(node)
        var a = AttributedString(s)
        for t in Self.json.tokens(in: s) {
            guard let r = Range(t.range, in: s), let ar = Range(r, in: a) else { continue }
            a[ar].foregroundColor = Color(nsColor: Theme.color(t.token))
        }
        return a
    }
}

// MARK: Model

@Observable
final class DataModel {
    weak var workspace: Workspace?
    struct Source {
        let name: String
        var table: DataTable?  // nil for a SQLite object until it's queried
        var isView = false
    }

    enum ExportFormat { case csv, json }

    var sources: [Source] = []
    var objects: [SQLiteDB.Object] = []
    var selected = 0
    var result: DataTable? { didSet { version += 1 } }
    var filter = ""
    var filterColumn: Int?
    var showSQL = false
    var showSchema = false
    var jsonlRaw = false
    var running = false
    var error: String?
    var loadError: String?
    var total: Int?  // SQLite: real row count of the selected table
    var history: [String] = []
    private(set) var displayedRows: [Int] = []
    private var displayed: (table: DataTable, rows: [Int], version: Int, filter: String, column: Int?)?
    var canExport: Bool { visibleRows != nil }

    func acceptDisplayed(_ rows: [Int]?, table: DataTable, version: Int, filter: String, column: Int?) {
        guard version == self.version, filter == self.filter, column == filterColumn else { return }
        displayedRows = rows ?? []
        displayed = rows.map { (table, $0, version, filter, column) }
    }
    private var generation = 0
    private var selectionGeneration = 0
    private var queryGeneration = 0
    @ObservationIgnored private var queryWorker: Task<DataTable, Error>?
    @ObservationIgnored private var activeDB: SQLiteDB?
    var version = 0  // bumps when the shown table changes (the grid rebuilds columns)

    @ObservationIgnored private var fileDB: SQLiteDB?    // SQLite file (read-only)
    @ObservationIgnored private var memoryDB: SQLiteDB?  // imports of CSV / JSONL / sheets
    @ObservationIgnored private var importedRevision: Int?
    @ObservationIgnored private var sql: Buffer?
    @ObservationIgnored private var historyKey = ""

    var shown: DataTable? { result ?? (sources.indices.contains(selected) ? sources[selected].table : nil) }

    func sqlBuffer(for b: Buffer) -> Buffer {
        if let sql { return sql }
        let first = sources.first.map { b.language == .sqlite ? SQLiteDB.quote($0.name) : SQLiteDB.tableName(for: $0.name) } ?? "t"
        let q = Buffer(url: nil, text: "SELECT * FROM \(first) LIMIT 1000;\n")
        q.language = .sql
        q.onCommandReturn = { [weak self] in self?.run(b) }
        sql = q
        return q
    }

    func setSQL(_ text: String) { sql?.replaceAll(with: text) }

    func load(_ b: Buffer) async {
        generation += 1
        let job = generation, sourceRevision = b.revision
        cancel()
        fileDB = nil
        result = nil
        loadError = nil
        historyKey = "sqlHistory." + (b.url?.path ?? b.id.uuidString)
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        let lang = b.language, url = b.url, text = b.text, name = b.url?.lastPathComponent ?? "untitled"
        let headerWas = sources.indices.contains(selected) ? sources[selected].table?.hasHeaderRow : nil
        sources = []
        do {
            switch lang {
            case .csv, .tsv:
                var t = await Task.detached { CSV.parse(text, delimiter: lang == .tsv ? "\t" : nil) }.value
                if let headerWas, headerWas != t.hasHeaderRow { t = t.togglingHeader() }  // keep the user's choice across edits
                guard !Task.isCancelled, job == generation, b.revision == sourceRevision else { return }
                sources = [Source(name: name, table: t)]
            case .jsonl:
                let t = await Task.detached { JSONLines.parse(text) }.value
                guard !Task.isCancelled, job == generation, b.revision == sourceRevision else { return }
                sources = [Source(name: name, table: t)]
            case .excel:
                guard let url else { return }
                let sheets = try await Task.detached { try XLSX.read(url) }.value
                guard !Task.isCancelled, job == generation, b.revision == sourceRevision else { return }
                sources = sheets.map { Source(name: $0.name, table: $0.table) }
            case .sqlite:
                guard let url else { return }
                let (db, objects) = try await Task.detached { () throws -> (SQLiteDB, [SQLiteDB.Object]) in
                    let db = try SQLiteDB(path: url.path)
                    return (db, try db.schema())
                }.value
                guard !Task.isCancelled, job == generation, b.revision == sourceRevision else { return }
                fileDB = db
                self.objects = objects
                sources = objects.map { Source(name: $0.name, table: nil, isView: $0.kind == .view) }
                if sources.isEmpty { loadError = "No tables in this database." }
            default:
                return
            }
            selected = min(selected, max(sources.count - 1, 0))
            importedRevision = nil
            version += 1
            if lang == .sqlite, !sources.isEmpty { select(selected) }
        } catch {
            guard !Task.isCancelled, job == generation, b.revision == sourceRevision else { return }
            loadError = "\(error)"
        }
    }

    func select(_ i: Int) {
        guard sources.indices.contains(i) else { return }
        selectionGeneration += 1
        let selectionJob = selectionGeneration, loadJob = generation
        cancel()
        selected = i
        result = nil
        filterColumn = nil
        total = nil
        version += 1
        guard let db = fileDB else { return }
        let name = sources[i].name, needsLoad = sources[i].table == nil
        guard needsLoad else { return }
        let queryJob = queryGeneration
        activeDB = db
        running = true
        Task {
            defer { if queryJob == queryGeneration { running = false; activeDB = nil; queryWorker = nil } }
            do {
                let worker = Task.detached { try db.query("SELECT * FROM \(SQLiteDB.quote(name)) LIMIT 100000") }
                queryWorker = worker
                let t = try await worker.value
                if queryJob == queryGeneration, loadJob == generation, selectionJob == selectionGeneration, sources.indices.contains(i) { sources[i].table = t; version += 1 }
                // Views may perform arbitrary computation; do not count them automatically.
            } catch {
                guard queryJob == queryGeneration, loadJob == generation, selectionJob == selectionGeneration else { return }
                loadError = "\(error)"
            }
        }
    }

    func toggleHeader() {
        cancel()
        guard result == nil, sources.indices.contains(selected), let t = sources[selected].table else { return }
        sources[selected].table = t.togglingHeader()
        filterColumn = nil
        importedRevision = nil  // SQL tables are re-imported with the new column names
        version += 1
    }

    func cancel() {
        queryGeneration += 1
        queryWorker?.cancel()
        activeDB?.interrupt()
        running = false
    }

    func run(_ b: Buffer) {
        guard let sqlText = sql?.text, !sqlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !running else { return }
        let query = sqlText.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        queryGeneration += 1
        let job = queryGeneration
        running = true
        let revision = b.revision, tables = b.language == .sqlite ? [] : sources.compactMap { s in s.table.map { (s.name, $0) } }
        let reuse = b.language == .sqlite ? fileDB : (importedRevision == revision ? memoryDB : nil)
        activeDB = reuse
        Task {
            defer { if job == queryGeneration { running = false; activeDB = nil; queryWorker = nil } }
            do {
                let db = try await Task.detached { () throws -> SQLiteDB in
                    let db: SQLiteDB
                    if let reuse { db = reuse } else {
                        db = try SQLiteDB(path: nil)
                        for (name, table) in tables { try db.importTable(table, as: SQLiteDB.tableName(for: name)) }
                    }
                    return db
                }.value
                guard job == queryGeneration, revision == b.revision else { return }
                activeDB = db
                let worker = Task.detached { try db.query(sqlText) }
                queryWorker = worker
                let t = try await worker.value
                guard job == queryGeneration, revision == b.revision else { return }
                if b.language != .sqlite { memoryDB = db; importedRevision = revision }
                result = t
                remember(query)
            } catch let e as SQLiteDB.Failure {
                guard job == queryGeneration, revision == b.revision else { return }
                // Point at the error: SQLite gives a UTF-8 byte offset into the SQL text.
                if let off = e.offset, let sql {
                    let utf8 = Array(sqlText.utf8)
                    let prefix = String(decoding: utf8.prefix(min(off, utf8.count)), as: UTF8.self)
                    let loc = (prefix as NSString).length
                    let line = sql.lines.line(at: loc), col = loc - sql.lines.start(ofLine: line) + 1
                    self.error = "Line \(line), column \(col): \(e.message)"
                    sql.reveal = NSRange(location: loc, length: 0)
                } else {
                    self.error = e.message
                }
            } catch {
                guard job == queryGeneration, revision == b.revision else { return }
                self.error = "\(error)"
            }
        }
    }

    private func remember(_ q: String) {
        history.removeAll { $0 == q }
        history.insert(q, at: 0)
        history = Array(history.prefix(20))
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    /// The same ordered indexes used by the grid.
    private var visibleRows: (DataTable, [Int])? {
        guard let displayed, displayed.version == version, displayed.filter == filter, displayed.column == filterColumn else { return nil }
        return (displayed.table, displayed.rows)
    }

    @discardableResult
    func export(_ format: ExportFormat, to url: URL) throws -> Int {
        guard let (table, rows) = visibleRows else { throw CocoaError(.userCancelled) }
        try (format == .csv ? table.csv(rows: rows) : table.json(rows: rows)).write(to: url, atomically: true, encoding: .utf8)
        return rows.count
    }

    func export(_ format: ExportFormat, name: String) {
        guard canExport else { return }
        let panel = NSSavePanel()
        let base = (name as NSString).deletingPathExtension + (result != nil ? "-query" : "")
        panel.nameFieldStringValue = base + (format == .csv ? ".csv" : ".json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try export(format, to: url)
            workspace?.flash("Exported \(count.formatted()) rows to \(url.lastPathComponent)")
        } catch {
            self.error = "Export failed: \(error.localizedDescription)"
        }
    }

    func copyAll(to pasteboard: NSPasteboard = .general) {
        guard let (t, rows) = visibleRows else { return }
        pasteboard.clearContents()
        pasteboard.setString(t.tsv(rows: rows), forType: .string)
    }
}

// MARK: Grid (NSTableView: virtualised, so millions of rows scroll fine)

struct DataGrid: NSViewRepresentable {
    let table: DataTable
    let version: Int
    let filter: String
    var filterColumn: Int? = nil
    var ordered: ([Int]?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = GridTableView()
        tv.usesAlternatingRowBackgroundColors = true
        tv.allowsMultipleSelection = true
        tv.allowsColumnReordering = true
        tv.columnAutoresizingStyle = .noColumnAutoresizing
        tv.style = .plain
        tv.gridStyleMask = [.solidVerticalGridLineMask]
        tv.rowHeight = 20
        tv.dataSource = context.coordinator
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.target = tv
        tv.doubleAction = #selector(GridTableView.showFullValue(_:))
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.tableView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.ordered = ordered
        context.coordinator.update(table: table, version: version, filter: filter, column: filterColumn)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var tableView: NSTableView?
        var table = DataTable(columns: [], rows: [])
        var ordered: (([Int]?) -> Void)?
        var work: Task<Void, Never>?
        var computeGeneration = 0
        var display: [Int] = []  // row indexes after filter + sort
        private var version = -1, filter = "", column: Int?, sort: (column: Int, ascending: Bool)?
        private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        func update(table: DataTable, version: Int, filter: String, column: Int?) {
            guard let tv = tableView else { return }
            if version != self.version {
                self.version = version
                self.table = table
                sort = nil
                rebuildColumns(tv)
            } else if filter == self.filter && column == self.column {
                return
            }
            self.filter = filter
            self.column = column
            recompute()
            tv.reloadData()
        }

        private func rebuildColumns(_ tv: NSTableView) {
            tv.tableColumns.forEach(tv.removeTableColumn)
            tv.sortDescriptors = []
            let num = NSTableColumn(identifier: .init("#"))
            num.title = "#"
            num.width = CGFloat(max(3, String(table.rows.count).count)) * 8 + 12
            tv.addTableColumn(num)
            let types = table.columnTypes()
            for (i, name) in table.columns.enumerated() {
                let c = NSTableColumn(identifier: .init("\(i)"))
                c.title = types[i] == .text || types[i] == .empty ? name : "\(types[i].glyph) \(name)"
                c.sortDescriptorPrototype = NSSortDescriptor(key: "\(i)", ascending: true)
                let longest = table.rows.prefix(200).map { $0.indices.contains(i) ? ($0[i]?.count ?? 4) : 0 }.max() ?? 0
                c.width = min(max(CGFloat(max(longest, name.count)) * 7.5 + 16, 50), 420)
                c.headerToolTip = "\(name) — \(types[i].rawValue)"
                tv.addTableColumn(c)
            }
        }

        private func recompute() {
            work?.cancel()
            computeGeneration += 1
            let job = computeGeneration, table = table, filter = filter, column = column, sort = sort
            display = []
            work = Task {
                ordered?(nil)
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                let idx = await Task.detached {
                    var idx = table.matching(filter, column: column)
                    if let s = sort {
                        let rows = table.rows
                        idx.sort { a, b in
                            let x = s.column < rows[a].count ? rows[a][s.column] : nil
                            let y = s.column < rows[b].count ? rows[b][s.column] : nil
                            return s.ascending ? DataTable.less(x, y) : DataTable.less(y, x)
                        }
                    }
                    return idx
                }.value
                guard !Task.isCancelled, job == computeGeneration else { return }
                display = idx
                ordered?(idx)
                tableView?.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { display.count }

        func tableView(_ tv: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            if let d = tv.sortDescriptors.first, let col = d.key.flatMap(Int.init) { sort = (col, d.ascending) } else { sort = nil }
            recompute()
            tv.reloadData()
        }

        func value(row: Int, column: Int) -> String? {
            guard display.indices.contains(row), table.rows.indices.contains(display[row]) else { return nil }
            let r = table.rows[display[row]]
            return column < r.count ? r[column] : nil
        }

        func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
            guard let col, display.indices.contains(row) else { return nil }
            let id = NSUserInterfaceItemIdentifier("cell")
            let field = (tv.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
                let f = NSTextField(labelWithString: "")
                f.identifier = id
                f.font = Self.font
                f.lineBreakMode = .byTruncatingTail
                f.cell?.truncatesLastVisibleLine = true
                return f
            }()
            if col.identifier.rawValue == "#" {
                field.stringValue = "\(display[row] + 1)"
                field.textColor = .tertiaryLabelColor
                field.alignment = .right
                field.toolTip = nil
            } else if let c = Int(col.identifier.rawValue) {
                let v = value(row: row, column: c)
                field.stringValue = v.map { $0.replacingOccurrences(of: "\n", with: "⏎") } ?? "NULL"
                field.textColor = v == nil ? .tertiaryLabelColor : (v.flatMap(Double.init) != nil ? .systemPurple : .labelColor)
                field.alignment = v.flatMap(Double.init) != nil ? .right : .left
                field.toolTip = (v?.count ?? 0) > 40 ? v : nil
            }
            return field
        }

        // Copy helpers used by the table's menu and ⌘C.
        func tsv(rows: IndexSet) -> String { table.tsv(rows: rows.compactMap { display.indices.contains($0) ? display[$0] : nil }) }
    }
}

final class GridTableView: NSTableView {
    weak var coordinator: DataGrid.Coordinator?

    /// Double-click a cell: show its whole value in a popover (selectable; JSON pretty-printed).
    @objc func showFullValue(_ sender: Any?) {
        let row = clickedRow, col = clickedColumn
        guard let c = coordinator, row >= 0, col >= 0, let dataCol = Int(tableColumns[col].identifier.rawValue) else { return }
        let raw = c.value(row: row, column: dataCol)
        var text = raw ?? "NULL"
        if let raw, raw.first == "{" || raw.first == "[", let node = try? JSON.parse(raw) { text = JSON.format(node) }

        let tv = NSTextView()
        tv.string = text
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textColor = raw == nil ? .tertiaryLabelColor : .labelColor
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        // Size to the content, within limits; long values scroll.
        let width: CGFloat = min(max(CGFloat(text.split(separator: "\n").map(\.count).max() ?? 0) * 7.3 + 30, 220), 640)
        tv.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 20
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(used + 16, 420)))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = tv

        let title = NSTextField(labelWithString: "\(tableColumns[col].title) · row \(c.display[row] + 1)\(raw.map { " · \($0.count) chars" } ?? "")")
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        let copyButton = NSButton(title: "Copy", target: nil, action: nil)
        copyButton.bezelStyle = .accessoryBarAction
        copyButton.controlSize = .small
        copyButton.sizeToFit()
        let copyTarget = ClosureTarget { [weak self] in self?.put(raw ?? "") }
        copyButton.target = copyTarget
        copyButton.action = #selector(ClosureTarget.fire)

        // Fixed layout: 12pt padding all round, header row (title … Copy) above the text.
        let pad: CGFloat = 12, gap: CGFloat = 6
        let headerH = max(copyButton.frame.height, 18)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width + pad * 2,
                                           height: pad + headerH + gap + scroll.frame.height + pad))
        let headerY = content.frame.height - pad - headerH
        copyButton.frame.origin = NSPoint(x: content.frame.width - pad - copyButton.frame.width, y: headerY)
        title.frame = NSRect(x: pad, y: headerY + (headerH - 16) / 2,
                             width: copyButton.frame.minX - pad - 8, height: 16)
        scroll.frame.origin = NSPoint(x: pad, y: pad)
        tv.textContainerInset = NSSize(width: 0, height: 2)
        [title, copyButton, scroll].forEach(content.addSubview)

        let vc = NSViewController()
        vc.view = content
        vc.preferredContentSize = content.frame.size
        objc_setAssociatedObject(vc, &Self.targetKey, copyTarget, .OBJC_ASSOCIATION_RETAIN)  // keep the button's target alive
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.show(relativeTo: frameOfCell(atColumn: col, row: row), of: self, preferredEdge: .maxY)
        tv.window?.makeFirstResponder(tv)
    }
    private static var targetKey = 0

    @objc func copy(_ sender: Any?) {
        guard let c = coordinator, !selectedRowIndexes.isEmpty else { return }
        put(c.tsv(rows: selectedRowIndexes))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p), col = column(at: p)
        guard let c = coordinator, row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        let menu = NSMenu()
        let dataCol = col >= 0 ? Int(tableColumns[col].identifier.rawValue) : nil
        if let dataCol {
            menu.addItem(item("Copy Cell") { self.put(c.value(row: row, column: dataCol) ?? "") })
            menu.addItem(item("Copy Column") {
                self.put((0..<c.display.count).map { c.value(row: $0, column: dataCol) ?? "" }.joined(separator: "\n"))
            })
        }
        menu.addItem(item(selectedRowIndexes.count > 1 ? "Copy \(selectedRowIndexes.count) Rows" : "Copy Row") {
            self.put(c.tsv(rows: self.selectedRowIndexes))
        })
        return menu
    }

    private func put(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(ClosureTarget.fire), keyEquivalent: "")
        let t = ClosureTarget(action)
        i.target = t
        i.representedObject = t  // keep the target alive with the item
        return i
    }
}

private final class ClosureTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}
