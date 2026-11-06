# 01 · Architecture, dependencies, decisions — ✅

## Decisions (user-confirmed)
- Swift, SwiftUI shell + AppKit NSTextView; minimum **macOS 26** (Liquid Glass); **direct download, no sandbox**; name **Anota**.
- Editor engine: CodeEditSourceEditor was approved, but its CodeEditLanguages dependency is a **1.4 GB** git clone with
  an all-or-nothing grammar bundle, so it was dropped. Engine = own NSTextView (TextKit 1) + tree-sitter (see 12).
- **Tree-sitter without CodeEditLanguages** (user prefers tree-sitter): swift-tree-sitter 0.25 package + **all grammars
  vendored** as generated C in `Vendor/TreeSitterGrammars` (one C target, 72 MB on disk / ~4 MB compressed), fetched from
  release tarballs by `scripts/vendor-grammars.sh`. Why not grammar packages: SwiftPM clones full history (~430 MB for
  TS/C++/Rust/JS) and the python/js/yaml manifests drop their scanner (fileExists bug → link error).
  Details in 12-syntax-highlighting.md.
- Formatting shells out to standard tools (prettier, gofmt, …) found on the login-shell PATH; see 13-formatting.md.
- Multiple windows, each with its own `Workspace`, session directory and focused menu routing.

## Layout (as built)
```
Package.swift                 tools 6.2; deps: swift-markdown, Yams, TOMLKit, swift-tree-sitter
Vendor/TreeSitterGrammars/    generated C for 13 grammars (scripts/vendor-grammars.sh — don't hand-edit)
Sources/AnotaCore/            pure logic, no AppKit, unit-tested
  Language.swift              detect language from filename
  Highlighter.swift           tree-sitter engine (13 grammars) or regex fallback (Markdown, HTML, CSS, shell, Java, Ruby, SQL)
  Queries/                    highlights.scm per tree-sitter grammar
  TextFile.swift              decode/encode: BOM, UTF-8/16/Latin-1, line endings, binary reject
  Session.swift               hot-exit store (session.json + buffers/<id>.txt)
  Node.swift                  shared tree, TreeItem (paths/filter), JSON parser/formatter, INI, plist
  Formats.swift               YAML (Yams), TOML (TOMLKit→JSON), Markdown→HTML page
  CodeFormatter.swift         external formatter runner (tool table, login PATH, timeout) + minimalEdit
  Search.swift                SearchOptions (case/word/regex/preserve case), FileSearch (folder search, globs)
Sources/Anota/                UI (defaultIsolation MainActor)
  AnotaApp.swift              Window scene, AppDelegate (hot exit, open-with), menus/shortcuts
  Workspace.swift             Buffer, EditorGroup, FileNode, Workspace
  EditorView.swift            NSTextView bridge, line-number ruler, current line, auto-indent, Theme
  ContentView.swift           sidebar, tab bar, vertical tabs, groups, status bar, toolbar, conflict banner
  Find.swift                  in-file find bar + find-in-files panel
  TreeViewer.swift            structured tree UI
  MarkdownPreview.swift       WKWebView preview
Tests/AnotaCoreTests/         Swift Testing, 36 tests (incl. one parameterized case per code grammar)
scripts/make-app.sh [debug]   builds build/Anota.app, ad-hoc signed
```

## Invariants worth keeping
- Editor text in memory always uses `\n`; the original line ending is restored on save (`TextFile`).
- One `NSTextStorage` per Buffer; each editor view adds its own layout manager (this is how split view works).
- Programmatic edits go through `Buffer.replace` / `replaceAll` so they are undoable and mark the buffer dirty.
- Session writes: buffer files first, then session.json (crash-safe ordering).

## Not done / limits
- [x] Multi-window: independent workspaces and recovery entries; prior single-window session migrates on first use
- Git: repo initialised, nothing committed yet (user hasn't asked).
