# Anota plan — index & status

The plan is version-controlled as of v0.4. The original single plan is kept as `00-original-plan.md` for reference;
the numbered files below replace it and are the ones to keep updated.

**Status legend:** ✅ **Done** · 🟡 **Partially done** (works, gaps listed) · ⬜ **Not done** · 🚫 out of v1 / dropped

What changed in each session, with status: **[CHANGELOG.md](CHANGELOG.md)**.

| # | Area | Status | One-line state |
|---|------|--------|----------------|
| [01](01-architecture.md) | Architecture, deps, decisions | ✅ Done | SPM, AnotaCore + Anota; own NSTextView editor + vendored tree-sitter grammars; 4 deps |
| [02](02-editor-core.md) | Editor core | 🟡 Partially done | Gutter, encodings/reopen, indentation/font settings, bracket matching, multiple selections; saved-state undo tracking still pending |
| [03](03-tabs-split.md) | Tabs, vertical tabs, split view | 🟡 Partially done | Four-direction splits, pin/Close Saved, persisted sizes and file drops; native pointer verification/preview tabs pending |
| [04](04-file-tree.md) | Directory tree | 🟡 Partially done | FSEvents, create/rename/Trash, shared fuzzy filter, file drag providers; native drop verification pending |
| [05](05-hot-exit.md) | Session restore (hot exit) | ✅ Done | Checkpoints, guarded quit, per-window recovery, persisted split sizes/view mode/scroll |
| [06](06-markdown.md) | Markdown editor/viewer | 🟡 Partially done | Safe Text/Split/Preview, scroll sync, local highlight.js, tasks, helpers and HTML/PDF export |
| [07](07-structured-viewers.md) | JSON / YAML / TOML / config | 🟡 Partially done | Tree for all; inline edit JSON only; TOML keys sorted |
| [08](08-search.md) | Find / replace / find in files | 🟡 Partially done | Cancellable bounded search, capture-correct replacement preview, symlink limits; no in-selection or .gitignore |
| [09](09-visual-ux.md) | Visual / UX polish | 🟡 Partially done | Settings, fonts and five themes; native pointer/Finder/visual verification pending |
| [10](10-polish-release.md) | Quick Open, settings, icon, packaging | 🟡 Partially done | Quick Open, Settings, recents, packaging scripts; actual Developer ID signing/notarization blocked by credentials |
| [12](12-syntax-highlighting.md) | Syntax highlighting (tree-sitter) | 🟡 Partially done | 14 grammars (incl. Bash), incremental; Log/.env/Batch/PowerShell + Markdown/HTML/CSS/Java/Ruby/SQL regex |
| [14](14-vscode-shortcuts.md) | VS Code shortcuts & multi-cursor | 🟡 Partially done | Line commands, multiple selections, Quick Open/command palette, Markdown shortcuts; no chords |
| [15](15-data-viewers.md) | Data viewer: SQLite / CSV / TSV / Parquet / JSON-lines / Excel | 🟡 Partially done | Background loads/sort/filter/query, ordered copy/export, SQL cancellation, CSV/XLSX fixes; no grid editing or Parquet |
| [13](13-formatting.md) | Formatting | 🟡 Partially done | Format Document / Selection / on Save, toolbar + right-click; no formatter settings |
| [11](11-later.md) | v1.1+ / non-goals | 🚫 Out of v1 | Promoted: initial LSP, multi-cursor, palette and windows. Git/terminal/plugins remain later |

## How to continue
1. Read `dev-progress/PROGRESS.md` (handoff notes) and this index.
2. Build/test: `rtk proxy swift test -c release` (81 core tests; 30 app tests reported, two optional probes skipped). Build: `rtk proxy sh scripts/make-app.sh debug`.
3. Pick the lowest-numbered 🟡/⬜ item in the area files' **Not done** lists; each file says where the code lives.
4. When you finish something, flip its checkbox in the area file, update the status row here, and add a line to CHANGELOG.md.

Suggested order: remaining native file-drop/column-selection verification, then the gaps recorded in FEATURE-PASS.md.

## Release status
v0.1 through v0.4 are previous releases. **v0.5 is prepared locally** with independent windows, editor
settings/multiple cursors, navigation, Markdown improvements, file management and initial LSP support.
`.version` and `.changelog` drive release notes. No push or publication is part of this update.
CI publishes `v0.5` when pushed to main if the tag does not exist, otherwise an RC tag.

## Requested feature pass — 2026-11-06

The requested items promoted from 11-later now have implementations. Per-area checkboxes and the summary table reflect this pass. See [feature verification](FEATURE-PASS.md). Finder Open With and selected pointer/visual checks passed; remaining native drag checks are recorded there. Developer ID signing/notarization is skipped at the user’s request.
