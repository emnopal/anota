# Anota plan — index & status

The plan is version-controlled as of v0.4. The original single plan is kept as `00-original-plan.md` for reference;
the numbered files below replace it and are the ones to keep updated.

**Status legend:** ✅ **Done** · 🟡 **Partially done** (works, gaps listed) · ⬜ **Not done** · 🚫 out of v1 / dropped

What changed in each session, with status: **[CHANGELOG.md](CHANGELOG.md)**.

| # | Area | Status | One-line state |
|---|------|--------|----------------|
| [01](01-architecture.md) | Architecture, deps, decisions | ✅ Done | SPM, AnotaCore + Anota; own NSTextView editor + vendored tree-sitter grammars; 4 deps |
| [02](02-editor-core.md) | Editor core | 🟡 Partially done | Gutter, encodings, line endings, auto-indent, fast long files, Go to Line; no bracket match / indent settings / reopen-with-encoding / multi-cursor |
| [03](03-tabs-split.md) | Tabs, vertical tabs, split view | 🟡 Partially done | Four-direction nested splits, persisted sizes, tab/file drops and pane-close cleanup; native pointer verification pending; no pin/preview tab |
| [04](04-file-tree.md) | Directory tree | 🟡 Partially done | Browse/open, background scans, file drag providers and workspace drops; no create/rename/trash or FSEvents |
| [05](05-hot-exit.md) | Session restore (hot exit) | ✅ Done | Checkpoints during typing, guarded quit/save conflicts, persisted split sizes; scroll/view mode not persisted |
| [06](06-markdown.md) | Markdown editor/viewer | 🟡 Partially done | Text/Split/Preview, safe HTML rendering, local images only; no scroll sync or code-block highlighting |
| [07](07-structured-viewers.md) | JSON / YAML / TOML / config | 🟡 Partially done | Tree for all; inline edit JSON only; TOML keys sorted |
| [08](08-search.md) | Find / replace / find in files | 🟡 Partially done | Cancellable bounded search, capture-correct replacement preview, symlink limits; no in-selection or .gitignore |
| [09](09-visual-ux.md) | Visual / UX polish | 🟡 Partially done | Native split/selection checks completed; pointer smoothness/file-drop verification pending; no themes/settings |
| [10](10-polish-release.md) | Quick Open, settings, icon, packaging | 🟡 Partially done | Icon, versioning (.version/.changelog), GitHub CI test+build+release done; no Quick Open / Settings / notarization |
| [12](12-syntax-highlighting.md) | Syntax highlighting (tree-sitter) | 🟡 Partially done | 14 grammars (incl. Bash), incremental; Log/.env/Batch/PowerShell + Markdown/HTML/CSS/Java/Ruby/SQL regex |
| [14](14-vscode-shortcuts.md) | VS Code shortcuts & multi-cursor | 🟡 Partially done | Line commands, Go menu, ⌘B/⇧⌘T; **multi-cursor noted for later**; no ⌘P / ⇧⌘P / chords |
| [15](15-data-viewers.md) | Data viewer: SQLite / CSV / TSV / Parquet / JSON-lines / Excel | 🟡 Partially done | Background loads/sort/filter/query, ordered copy/export, SQL cancellation, CSV/XLSX fixes; no grid editing or Parquet |
| [13](13-formatting.md) | Formatting | 🟡 Partially done | Format Document / Selection / on Save, toolbar + right-click; no formatter settings |
| [11](11-later.md) | v1.1+ / non-goals | 🚫 Out of v1 | LSP, git, terminal, multi-cursor, command palette, multi-window |

## How to continue
1. Read `dev-progress/PROGRESS.md` (handoff notes) and this index.
2. Build/test: `rtk proxy swift test -c release` (81 core tests; 30 app tests reported, two optional probes skipped). Build: `rtk proxy sh scripts/make-app.sh debug`.
3. Pick the lowest-numbered 🟡/⬜ item in the area files' **Not done** lists; each file says where the code lives.
4. When you finish something, flip its checkbox in the area file, update the status row here, and add a line to CHANGELOG.md.

Suggested order: native pointer/file-drop verification (03/04/09), then Quick Open/Settings (10), then remaining gaps.

## Release status
v0.1, v0.2.0, v0.3.0 and v0.3.1 are previous releases. **v0.4 is prepared locally** with four-direction workspaces,
drag fixes and audit hardening; `.version` and `.changelog` drive release notes. No push or publication is part of
this update. CI publishes `v0.4` when pushed to main if the tag does not exist, otherwise an RC tag.
