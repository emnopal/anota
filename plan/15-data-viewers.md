# 15 · Data viewer: SQLite / CSV / TSV / Parquet / JSON-lines / Excel (DuckDB-extension style) — 🟡 Phases 1–3 done (v0.4), Parquet ⬜

Goal: open `.sqlite/.db/.sqlite3`, `.csv`, `.tsv`, `.parquet`, `.jsonl/.ndjson`, `.xlsx` and get what the DuckDB VS Code extension gives: a schema/table
list, a fast virtualised result grid, and a SQL box to query the file — including CSV/TSV with SQL.

## Status
✅ Built (phases 1–3): `Sources/AnotaCore/{DataTable,SQLiteDB,XLSX}.swift` (CSV/TSV/JSONL parsers, SQLite wrapper,
ZIP+XML xlsx reader; tests in `Tests/AnotaCoreTests/DataTests.swift` + `Fixtures/sample.xlsx`),
`Sources/Anota/DataView.swift` (DataView, DataModel, DataGrid = NSTableView). Document model: chose the light option —
SQLite/Excel are a `Buffer` with no text (`Language.isBinaryData`), so tabs/session/close work unchanged; writes are
refused (`Workspace.write` + precondition in `Buffer.write`). Engine: system SQLite only (no DuckDB yet).
Not visually verified (opened all five formats in an isolated instance without errors).

Remaining gaps: no "Allow Writes", no grid editing, no JSONL record tree, no lazy row fetch (caps: 100K rows per query,
200K per sheet), CSV not streamed, Parquet/DuckDB (phase 4). Schema panel, counts, error positions, history, export,
column filter, type guess, header toggle, rainbow CSV and JSONL Raw view were added in the follow-up pass.

## v0.4 follow-up
- [x] Background data loads, SQL, sorting/filtering and tree parsing; stale tasks cannot replace newer data
- [x] SQL deadline/interruption, sorted/filtered copy/export, CSV empty-record handling and unique SQL column names
- [x] Excel 1904 date system; malformed XML/shared-string indexes report errors
- [x] Automated data/recovery acceptance checks; interactive large-data benchmarking remains optional

## Scope — ✅ done · 🟡 partial · ⬜ not done
**SQLite**
- [x] ✅ Opens read-only (`SQLITE_OPEN_READONLY`; SQLite refuses writes — tested)
- [ ] ⬜ "Allow Writes" toggle per tab
- [x] ✅ Table/view picker + **schema panel** (toolbar sidebar button): tables/views, columns with type, PK (key icon),
      NOT NULL, and indexes (`pragma_index_list`); clicking a table header selects it
- [x] ✅ Picking a table shows `SELECT * … LIMIT 100000`; real total via `count(*)` in the background
      (footer: "first 100,000 of 2,345,678")
- [x] ✅ SQL box (reuses `EditorView`, SQL highlighting) + ⌘↩ / Run; result replaces the grid ("Show Table" returns);
      errors show "Line L, column C: message" and the caret jumps there (`sqlite3_error_offset`)
- [x] ✅ Query history (last 20 per file, UserDefaults `sqlHistory.<path>`, clock menu in the SQL box)
- [x] ✅ Export the rows shown (filter and displayed sort apply) as CSV / JSON (array of objects), Copy All as TSV

**CSV / TSV**
- [x] ✅ RFC 4180 parser (quotes, `""`, embedded newlines, CRLF, ragged rows → NULL), delimiter sniffing (`,` `;` tab `|`),
      header detection; decoding via the normal text path (BOM etc.). ✅ Byte-level scanner: 11 MB / 400K rows in
      0.16 s (release). 🟡 Still not streaming: the whole file is in memory (text + table)
- [x] ✅ Modes **Grid** (default) / **Text** with **rainbow columns** (`Highlighter` `.columns` engine, delimiter sniffed;
      per-line, so a quoted field spanning lines shifts colours until the next record)
- [x] ✅ Grid: sort by header, row numbers, column resize/reorder, row filter **+ column picker** (filter one column),
      **type guess** (integer / decimal / boolean / date / text) as a header glyph (`#`, `#.#`, `✓`, `◷`) + tooltip
- [x] ✅ "Header row" checkbox (CSV/TSV/Excel): first row ↔ column names (`DataTable.togglingHeader`), kept across edits
- [x] ✅ SQL over the file: in-memory SQLite table named after the file (`people.csv` → `people`), re-imported after edits
- [ ] ⬜ Editing in the grid

**Parquet** (`.parquet`)
- [ ] ⬜ Not started — needs DuckDB (phase 4, Decisions 1)

**JSON-lines** (`.jsonl`, `.ndjson`)
- [x] ✅ Text stays editable; Grid: one row per line, columns = union of top-level keys (all lines), nested values as
      compact JSON, invalid lines skipped and reported with line number (footer)
- [x] ✅ **Table / Raw** toggle: Raw shows every record pretty-printed and coloured (lazy list), invalid lines in red,
      filter applies; double-click or "Show in Text" jumps to the line
- [ ] ⬜ Tree view of the selected record
- [x] ✅ SQL via in-memory import

**Excel** (`.xlsx`, `.xlsm`; `.xls` out of scope)
- [x] ✅ Native reader: ZIP central directory + DEFLATE (`Compression`) + `XMLParser`; shared/inline strings, booleans,
      date styles → ISO dates, cached formula values; fixture-tested
- [x] ✅ Sheet tabs (segmented control up to 6 sheets, menu above); header row auto-detected + "Header row" toggle;
      merged cells show their value in the top-left cell (Excel stores it there; other cells empty)
- [x] ✅ Read-only; ✅ SQL over sheets (one table per sheet)

**Shared grid**
- [x] ✅ `NSTableView` in SwiftUI (virtualised), monospaced cells, NULL dimmed, numbers right-aligned purple, newlines as ⏎,
      tooltip for long values, copy cell / row / column, ⌘C = rows as TSV; double-click a cell → popover with the
      full value (selectable, scrolls, JSON pretty-printed, Copy)
- [ ] ⬜ Lazy fetch: rows are fully loaded; caps 100K per query, 200K per sheet (footer says "first N shown")

## Decisions to make
1. **Engine.** With Parquet in scope the recommendation changes to **DuckDB** (duckdb-swift or a vendored prebuilt
   library): it reads CSV/TSV (`read_csv` with sniffing), Parquet, JSON-lines (`read_json`/`read_ndjson`) and SQLite
   files, all with one SQL dialect and fast columnar scans — exactly the DuckDB extension's model.
   Costs: ~50 MB+ added to the app, and the SwiftPM checkout is heavy (same issue as CodeEditSourceEditor) → vendor a
   prebuilt `libduckdb` (xcframework / static lib) like the tree-sitter grammars instead of a package.
   **To verify before building:** which extensions are built into the prebuilt lib (parquet and json usually are;
   **excel and sqlite_scanner may need `INSTALL`, i.e. a network download** — Anota makes no network requests today,
   so they must be statically linked or replaced by the native readers below).
   Fallback without DuckDB: system SQLite (`import SQLite3`, zero dependency) for SQLite + SQL-over-CSV/JSONL/XLSX via
   in-memory import, and **no Parquet**.
   Either way, keep native readers for CSV, JSON-lines and XLSX (small, testable, work without SQL).
2. ✅ **Decided: Buffer without text** (`Language.isBinaryData`) instead of a `TabContent` enum — smallest change;
   revisit if binary documents need their own state (e.g. write mode). Original options: **Document model.** Tabs hold a text `Buffer`; a SQLite file is binary. Options: (a) a `TabContent` enum
   (`.text(Buffer)` / `.database(DatabaseDocument)`) through `EditorGroup`, session, tab views; (b) a `Buffer` subtype.
   Recommended (a); touches Workspace, Session, TabBar, GroupView. CSV stays a `Buffer` (it is text) with a Grid mode.
3. **Large CSV.** Grid parses off the main thread into a column store; in-memory SQLite import only when the SQL pane
   is first used.
4. **Writes.** v1 read-only for SQLite; CSV grid edits only after the grid is stable.

5. **Phasing.** (1) shared grid + CSV/TSV + JSON-lines (native, no engine); (2) SQLite viewer + SQL pane;
   (3) XLSX native reader; (4) engine for SQL-over-files + Parquet (DuckDB, after the verification above).

## Out of scope for now
Legacy `.xls`, writing Excel/Parquet, charts, remote databases. Joins across files come free with DuckDB
(`SELECT … FROM 'a.csv' JOIN 'b.parquet'`) but not with the SQLite fallback.

## Verify (when built)
Unit: XLSX fixture (shared strings, dates, empty cells, 2 sheets), JSON-lines with ragged keys and a bad line,
Parquet fixture via the engine (types, NULLs, row groups). CSV parser edge cases (quotes, CRLF, embedded newlines, ragged rows, BOM), delimiter sniffing, type guessing,
SQLite schema read on a fixture DB, CSV → in-memory table → query. Manual: 1M-row CSV scrolls smoothly; read-only DB
refuses `DELETE`.
