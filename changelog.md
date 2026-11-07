# Changelog

Newest first. Each release's notes are the section whose heading matches `.version`.
A push to `main` that doesn't change `.version` is published as a pre-release `v<version>-rc-<UTC datetime>`.

## v0.5.1

- Fixed a flaky CI timing test, renamed `.changelog` to `changelog.md`, and refreshed the README/showcase hero.

## v0.5

Independent windows, a more capable editor, and a complete Markdown workflow.

- Each window has its own workspace and recovery session. Finder Open With reuses the most recently active
  window, or creates one when needed, without leaving an extra empty window.
- Added Settings for font family/size, indentation width, spaces versus tabs, wrap defaults and five themes:
  System, Light, Dark, Solarized and Midnight.
- Added matching-bracket highlighting, document indentation overrides and explicit Reopen with Encoding.
- Multiple cursors support successive typing, deletion, newline and undo; use ⌘D or add cursors above/below.
- Pin tabs and use Close Saved to keep unsaved work and pinned documents open.
- Files refresh after disk changes; dirty buffers retain conflict handling. Recursive watcher startup runs
  off the main thread to avoid blocking workspace restoration.
- Create files/folders, rename inline and Move to Trash from the directory tree; unsaved changes block Trash.
- Quick Open (⌘P), the tree filter and command palette (⇧⌘P) share fuzzy matching. Workspace indexing reuses
  file-search exclusions, and relative paths resolve correctly through macOS temporary-directory aliases.
- Persist document view modes, scroll positions, pinned state and explicit read encodings across sessions.
- Markdown adds proportional editor/preview scroll sync, task checkboxes, locally bundled code-block
  highlighting, HTML/PDF export, bold/italic shortcuts and list continuation on Return.
- Find, replace and project-search inputs support multiple lines. Added recent files/folders through macOS.
- Added a configurable stdio language-server client for completion, go to definition and diagnostics.
- Fixed multiple selections disappearing during successive typing, line beginnings clipped by the ruler,
  and preview scroll-only changes not reaching WebKit.
- Added a screenshot showcase and a new README hero using the demo workspace.
- Added local DMG packaging and Developer ID/notarization scripts; signing/notarization execution remains skipped.

Verification: 42 app tests and 90 core tests passed in release mode, with the performance benchmark and real
SourceKit-LSP completion enabled. Separate-process crash recovery passed. Native Finder Open With was verified
with one, two and no existing workspace windows. Native file drops to Finder and Option-drag column selection
still need human verification; see plan/FEATURE-PASS.md.

## v0.4

Four-direction workspaces, drag-and-drop improvements, and audit fixes.

- Split panes left, right, top, or bottom from the toolbar or tab menu; nest horizontal and vertical splits,
  resize either axis, and restore split orientation and sizes across sessions. ⌘\ splits right; ⌥⌘\ splits below.
- Drag horizontal or vertical tabs onto editor edges to split, or into another pane's center/tab strip to move.
  Larger edge zones and destination previews make targeting easier; cross-pane moves commit on release to keep
  the source gesture alive. Closing a pane cleans up drag state without erasing surviving tab geometry.
- Drag directory-tree files onto an editor or tab strip to open there, or onto an editor edge to open in a split.
- Finder Open With uses the existing window and updates the active tab/editor; reordering preserves the active editor.
- Recovery checkpoints continue during typing; failed recovery writes are reported, and quitting offers Retry,
  Save As, or Cancel Quit if recovery cannot be saved. Coordinated saves detect changed disk contents before replacement.
- Search runs cancellable background work with time/result limits, avoids symlink escapes, reports truncation,
  and uses the same regex captures for replacement previews and applied changes.
- Data loads, filtering, sorting, SQL, and tree parsing run off the main thread; stale loads cannot replace newer data.
  SQL can be interrupted and has a deadline; copy/export follow displayed sort/filter order.
- CSV preserves empty records; imported SQL column names remain unique; Excel supports 1904 dates and reports
  malformed XML or invalid shared-string indexes instead of silently returning incomplete results.
- Markdown preview escapes raw HTML, blocks document JavaScript and remote images, restricts link schemes,
  and keeps scroll position across updates.
- Added core, hosted-view, recovery, data, and drag regression tests.

Verification: release test suite passes (81 core tests; 30 app tests reported, including two optional probes skipped).
Native UI confirmed mixed nested splits and tab selection after closing a pane. Pointer smoothness and native
file-drop delivery still need manual verification: the computer-control tool returned `noWindowsAvailable`.

## v0.3.1

Security hardening for the data viewer.

- Hardening: malformed or hostile .xlsx files throw instead of crashing (ZIP offsets bounds-checked, part sizes and
  compression ratio capped, column references limited to A…XFD, sheets capped at 20M cells — also when a single far-right
  cell widens the sheet); SQLite files open with
  `trusted_schema = OFF` and `query_only = ON`

## v0.3.0

Data viewer (CSV, TSV, JSON Lines, SQLite, Excel), auto-closing pairs.

- Data viewer (Grid view) for CSV, TSV, JSON Lines, SQLite (`.sqlite`/`.db`, read-only) and Excel `.xlsx` (read-only):
  - fast virtualised grid: sort by header (numbers numerically, NULLs last), row filter, row numbers, NULL dimmed
  - copy cell / row / column from the right-click menu; ⌘C copies selected rows as TSV
  - table / view picker (SQLite) and sheet picker (Excel); Excel dates, booleans and cached formula values
  - CSV: quoted fields, line breaks in fields, separator and header detection; JSON Lines: one column per key,
    invalid lines reported
  - SQL box (⌘↩ runs): SQLite files queried directly; CSV/TSV/JSONL/sheets loaded into an in-memory database,
    one table per file or sheet
  - saving never writes to SQLite / Excel files
  - schema panel (SQLite tables, columns, types, keys, indexes; column types guessed for other formats)
  - real row counts for big SQLite tables, column filter, type glyphs in headers, "Header row" toggle
  - SQL errors point at the line and column; query history; export rows as CSV or JSON
  - CSV/TSV text view colours each column differently (rainbow CSV); faster CSV parsing
  - JSON Lines: Table / Raw toggle (each record pretty-printed and coloured)
  - double-click a cell to see its full value in a popover (selectable, JSON pretty-printed, Copy button)
- Editor: auto-closing pairs `() [] {} "" '' `` <>` like VS Code — wrap the selection, type over the closer,
  Backspace deletes an empty pair, Return inside `{}`/`[]`/`()` indents and puts the closer on its own line, a lone
  closing bracket outdents; quotes don't pair after letters (don't), `<` pairs only in HTML/XML and for generics
- Fix: a file opened from outside (Finder, Dock) didn't show as the active tab — the tab bar didn't track the
  active-tab change; files in the tree now also open on click, the tree highlight just follows the active tab
- Fix: opening a file no longer flashes it uncoloured (normal-sized files are coloured before the first frame)
- Fix: the toolbar's view-mode switch kept stale segments after switching to a file with fewer (or no) modes

## v0.2.0

Performance, more languages, VS Code shortcuts.

- Long files: incremental tree-sitter parsing, colours as layout-manager temporary attributes (no relayout),
  highlighting in slices, background first parse, O(log n) line numbers
- Folder tree: background scanning, clicking a folder name expands it, expansion kept across refreshes
- New: log files, .env (with tree view), Batch, PowerShell highlighting; Bash/Zsh via tree-sitter
- Tabs: + button and double-click on the empty tab bar for a new file
- VS Code shortcuts: line comment, move/copy/delete line, insert line, indent, ⌘L, ⌘D, Go to Line, tab cycling, ⌘1–3,
  reopen closed tab, ⌘B / ⇧⌘E

## v0.1

First release.

- Editor: tree-sitter highlighting for 13 languages (regex for the rest), line numbers, current-line highlight,
  auto-indent, word wrap (toolbar, View menu, right-click, ⌥Z), per-file undo
- Encodings (UTF-8 / BOM / UTF-16 / Latin-1) and line endings (LF / CRLF / CR)
- Tabs: horizontal or vertical (pinned "Tabs" sidebar section); drag to reorder or move between panes;
  Close Others / Close Tabs to the Left / to the Right / Close All
- Split view with equal-width panes and draggable dividers; empty panes can be closed
- Directory tree, session restore (hot exit)
- Markdown Text / Split / Preview
- Tree viewer for JSON, YAML, TOML, INI / .env, plist; inline JSON value editing
- Find & replace (VS Code-style options, async matching, jumps to match while typing) and Find in Files
- Format Document (⌥⇧F) and Format Selection (⌥⇧⌘F) via prettier, gofmt, rustfmt, clang-format, swift-format,
  ruff/black, taplo, shfmt, xmllint; built-in JSON formatter; optional Format on Save
- App icon
