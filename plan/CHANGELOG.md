# What's changed so far (2026-11-05)

Status: ✅ **Done** · 🟡 **Partially done** (works; gaps listed in the area file) · ⬜ **Not done**

## Session 1: plan
| Change | Status | Area |
|---|---|---|
| Written plan (features, architecture, milestones M0–M7); decisions: Swift + macOS 26, direct download, name Anota | ✅ Done | 00, 01 |

## Session 2: build milestones 0–6
| Change | Status | Area |
|---|---|---|
| M0 skeleton: SwiftPM app, open / save / save as / save all, `scripts/make-app.sh` | ✅ Done | 01, 10 |
| M1 editor core: line numbers, current line, auto-indent, wrap, encodings, line endings, status bar, disk-change banner | 🟡 Partially done | 02 |
| M2 tabs: horizontal + vertical tabs, drag reorder / move between groups, split ⌘\ | 🟡 Partially done | 03 |
| M2 directory tree: lazy folder tree, open, reveal, copy path | 🟡 Partially done | 04 |
| M3 hot exit: no quit prompt, unsaved + untitled buffers and layout restored (verified) | ✅ Done | 05 |
| M4 Markdown: Text / Split / Preview with swift-markdown + WKWebView | 🟡 Partially done | 06 |
| M5 structured viewers: JSON / YAML / TOML / INI / .env / plist tree, JSON inline edit, format + minify JSON | 🟡 Partially done | 07 |
| M6 search: VS Code-style find bar, find in files with globs + replace all | 🟡 Partially done | 08 |
| Mac-native shell (sidebar, toolbar, glass find bar, SF Symbols); **not visually reviewed yet** | 🟡 Partially done | 09 |
| M7 polish: Quick Open, Settings, icon, notarization | ⬜ Not done | 10 |
| CodeEditSourceEditor: resolve stalled (1.4 GB CodeEditLanguages), dropped | 🚫 Dropped | 01, 11 |

## Session 3: plan split
| Change | Status | Area |
|---|---|---|
| Plan split into `plan/` area files with per-item status (git-ignored, like `dev-progress/`) | ✅ Done | README |

## Session 4: tree-sitter
| Change | Status | Area |
|---|---|---|
| Tree-sitter highlighting for JSON, YAML, TOML, INI/.env (real grammars, no CodeEditLanguages) | ✅ Done | 12 |
| Tree-sitter for Python, JavaScript/JSX, TypeScript, TSX, Go, C, C++, Rust, Swift | ✅ Done | 12 |
| All grammars vendored via `scripts/vendor-grammars.sh` (upstream packages too big / broken manifests) | ✅ Done | 01, 12 |
| `.tsx` language + function colour | ✅ Done | 12 |
| Tree-sitter for Markdown, HTML, CSS, Bash, Java, Ruby, SQL (still regex) | ⬜ Not done | 12, 11 |
| Incremental parsing for large files | ⬜ Not done | 12 |

## Session 5: formatting
| Change | Status | Area |
|---|---|---|
| Format Document ⌥⇧F via prettier / gofmt / rustfmt / clang-format / swift-format / ruff / black / taplo / shfmt / xmllint, built-in JSON fallback | ✅ Done | 13 |
| Format on Save toggle | ✅ Done | 13 |
| Minimal-edit apply for format and Replace All (one undo, cursor kept) | ✅ Done | 02, 13 |
| Format Selection, formatter settings, project-local prettier | ⬜ Not done | 13 |

## Overall
- Tests: 36 passing (`swift test`). Build: clean, no warnings.
- **Biggest open risk:** nobody has looked at the UI yet (see 09).
- Next suggested: human visual review → 10 (Quick Open, Settings) → gaps in 03/04 → rest.

- ✅ Sidebar: in vertical-tab mode a pinned **Tabs** section sits between the Files/Search picker and the project tree or search panel (visible in both modes; height capped at 260pt). Replaces the old "Open Editors" section inside the file list.
- ✅ Split panes: custom `SplitPanes` replaces HSplitView for editor groups; adding/removing a pane re-divides width equally; dividers draggable (min 220pt). Markdown Text|Preview split still uses HSplitView.
- ✅ Tab menu: Close Tabs to the Left / to the Right / Close All; File ▸ Close All Tabs (⌥⌘W).
- ✅ Format Selection (⌥⇧⌘F): dedents the fragment, formats it, restores indent + trailing newline (`formatFragment`, tested). Tools that need a whole file (e.g. gofmt on a partial snippet) may reject fragments.
- ✅ Format entry points: toolbar Format button (selection if any, else document) and editor right-click Format Document / Format Selection.
- ✅ Find bar: matching runs off-main (cancellable) and jumps to the nearest match while typing; focus is taken reliably on ⌘F (yield + resign editor first responder); option toggles/arrows have 22pt+ hit boxes with a VS Code-style "on" chip (`OptionToggleStyle`, also used in Find in Files).
- 🟡 Find bar cursor: arrow instead of the editor I-beam over the bar (CodeTextView mouseMoved/cursorUpdate check `find.barFrame`). Not visually verified.
- ✅ Word wrap: toolbar toggle (highlighted when on) and editor right-click "Word Wrap" (checkmark); View ▸ Word Wrap ⌥Z already existed.
- ✅ App icon: `scripts/make-icon.swift` renders `assets/AppIcon.icns` (+ 1024 PNG); make-app.sh bundles it (CFBundleIconFile). Toolbar Word Wrap/Format labels reverted to default style.
- ✅ Fix: empty split panes can be closed (⌘W on an empty pane, or "Close Pane" button); clicking an empty pane focuses it.

## 2026-11-05 — v0.1 finalization
- ✅ Versioning: `.version` (0.1) drives CFBundleShortVersionString; build number = commit count (`BUILD_NUMBER` overrides).
- ✅ `.changelog` with `## v0.1` section; `scripts/release-notes.sh` extracts it.
- ✅ `scripts/release-tag.sh`: `v<version>` if untagged, else `v<version>-rc-<UTC YYYYMMDDHHMMSS>`.
- ✅ GitHub Actions `ci.yml` (macos-26): swift test → make-app.sh → zip artifact; on push to main, `gh release create` (rc = pre-release).
- ✅ README: install, versioning & releases, new shortcuts/features.
- ✅ Release assets: DMG containing Anota.app + Applications link (`Anota-<tag>-macos-<arch>.dmg`), arch from lipo, stated in notes; README shows icon.

## 2026-11-05 — performance + languages
- ✅ Long files: incremental tree-sitter (`Highlighter.edited/update`), temporary-attribute colouring in 100K slices, debounced reparse >300K chars, background first parse, `LineIndex` for gutter/caret.
- ✅ Folder tree: async scans, folder-name click toggles (root cause of "can't expand": only the chevron toggled; name click just selected), `expanded` stored on FileNode, refresh only changed dirs.
- ✅ Languages: log, dotenv (tree view via INI), batch, powershell (regex); bash/zsh tree-sitter (vendored v0.25.0).
- ✅ Tabs: NewTabButton (doc.badge.plus) + double-click empty strip, horizontal and vertical.
- 🟡 Not visually verified; log has highlighting only (no level filter view).
- ✅ VS Code shortcuts: Selection menu (⌘/ comment, ⌥↑↓ move, ⇧⌥↑↓ copy, ⇧⌘K delete, ⌘↩/⇧⌘↩ insert, ⌘]/⌘[ indent, ⌘L, ⌘D single-selection), Go menu (⌃G go to line, ⌃Tab/⌥⌘←→ tabs, ⌘1–3 groups), ⇧⌘T reopen, ⌘B sidebar, ⇧⌘E explorer. Logic in AnotaCore `LineEdits` + `Language.lineComment` (tested). Not done: ⌘P, ⇧⌘P, multi-cursor, ⌘K chords.

## 2026-11-05 — v0.2.0 prepared
- ✅ `.version` → 0.2.0; `.changelog` Unreleased → `## v0.2.0`; README status.
- ✅ New plan area 14 (VS Code shortcuts); **multi-cursor design noted there for later**.
- ✅ Plan areas 02/04/12 and index updated for the v0.2.0 work.

## 2026-11-05 — planned
- ⬜ Plan area 15: SQLite / CSV / TSV viewer in the style of the DuckDB VS Code extension (no code yet).
- ⬜ Plan 15 extended: Parquet, JSON-lines, Excel (.xlsx); engine recommendation now DuckDB (Parquet), phasing added.

## 2026-11-05 — data viewer phases 1–3
- ✅ CSV/TSV/JSONL/SQLite/XLSX grid + SQL box (system SQLite, in-memory import for files). 7 new tests.
- ✅ Fix: tree selection follows the active tab (re-clicking a file after switching tabs did nothing).
- 🟡 Not visually verified; gaps listed in 15-data-viewers.md.
- ✅ Docs: plan 15 scope marked done/partial/not done per item; README layout, limits, ⌘↩ note; .changelog Unreleased expanded.

## 2026-11-05 — data viewer partials finished
- ✅ Schema panel, SQLite counts, SQL error position, query history, export CSV/JSON, column filter, type glyphs, header toggle, rainbow CSV, faster CSV scanner, Excel sheet tabs, JSONL Table/Raw toggle. 5 new tests (54).
- 🟡 Not visually verified (isolated-instance smoke test only).
- ✅ Auto-closing pairs () [] {} "" '' `` <> with wrap / type-over / pair-backspace / block Return / outdent (AutoPair, 2 tests).
- ✅ Grid: double-click a cell shows the full value in a popover.

## 2026-11-05 — v0.3.0 prepared
- ✅ `.version` → 0.3.0; `.changelog` Unreleased → `## v0.3.0`; README + plan status.
- ✅ Fix: outside-folder tab stuck (List selection write-back re-opened the old file) — tree rows open on tap, selection is highlight-only.
- ✅ Fix: stale toolbar mode picker — item always present, picker re-identified by its mode set.
- ✅ Fix (real cause): TabBar read group.active only inside ForEach closure → not tracked on external open. Now read in body.
- ✅ Fix: no uncoloured flash on open (sync first restyle ≤300K chars). Diagnostics showed no window recreation/restart on external open.

## 2026-11-05 — v0.3.1
- ✅ Security review fixes: XLSX ZIP bounds checks, inflate size/ratio caps, column refs ≤ XFD, 20M-cell cap; SQLite trusted_schema OFF + query_only. 2 tests.

## 2026-11-06 — v0.4 prepared
- ✅ Four-direction nested workspaces, persisted split ratios, toolbar/context-menu actions and Split Below shortcut.
- ✅ Tab edge/center/strip drop handling, deferred cross-pane commit, cancellation and pane-close geometry cleanup.
- ✅ Directory-tree file providers and editor/tab-strip file drops, including edge splits.
- ✅ Finder Open With routing, active-tab updates and editor-preserving tab reordering.
- ✅ Audit follow-up: periodic recovery, quit failure handling, coordinated save conflicts, bounded/cancellable search,
  matching replacement previews, safe Markdown rendering, background data work, SQL interruption and CSV/XLSX fixes.
- ✅ Release tests: 81 core tests and 30 app tests reported; two optional probes skipped. Signature verification passed.
- ✅ Native UI: mixed nested splits and selecting the surviving tab after pane closure.
- 🟡 Native pointer smoothness and file-drop delivery remain unverified due to CUA `noWindowsAvailable` errors.
- ✅ `.version` → 0.4, release notes and README updated; plan now version-controlled. Publication not performed.
