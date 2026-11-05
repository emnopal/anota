# Anota

A simple, fast code editor for macOS.
Written in Swift (SwiftUI + AppKit).

> Status: early development (v0.1). Core features work and are unit-tested; the UI has not had a visual polish pass yet.

## Features

- **Editor:** syntax highlighting (tree-sitter for 13 languages, regex for the rest), line numbers,
  current-line highlight, auto-indent, word wrap (⌥Z), and per-file undo
- **Encodings and line endings:** UTF-8 / UTF-8 BOM / UTF-16 / Latin-1 detection, LF / CRLF / CR,
  convertible from the status bar
- **Tabs:** horizontal, or vertical in the sidebar (⌥⌘T). Drag to reorder or to move between panes
- **Split view (⌘\\):** the same file in two panes is edited live in both
- **Directory tree:** open a folder to see a lazy-loading file tree. `.git`, `node_modules` and `.build` are hidden
- **Session restore (hot exit):** quitting never asks to save. Unsaved and untitled files, tabs, splits and the
  open folder all come back on relaunch. A crash loses at most about one second of typing
- **Markdown:** Text / Split / Preview (⇧⌘V), GitHub-style rendering, light and dark
- **JSON / YAML / TOML / INI / .env / plist:** a tree view in the style of Firefox's JSON viewer, with:
  - filter, expand/collapse all
  - copy value / copy path
  - jump to source
  - inline editing of JSON values
- **Find & replace (⌘F / ⌥⌘F):** in the style of VS Code. Match case, whole word, regex (`$1` templates), preserve case
- **Find in files (⇧⌘F):** include/exclude globs, results grouped by file, a replace preview, and Replace All
- **Formatting:** Format Document (⌥⇧F) and an optional Format on Save, using the standard tool for each language
  (see below)
- **External changes:** files changed on disk reload. If you also have unsaved edits, Anota asks which version to keep

### Syntax highlighting

| Engine | Languages |
|---|---|
| tree-sitter | JSON/JSONC, YAML, TOML, INI/.env/.properties, Python, JavaScript/JSX, TypeScript, TSX, Go, C, C++, Rust, Swift |
| regex | Markdown, HTML/XML, CSS, shell, Java/Kotlin, Ruby, SQL |

### Formatters

Anota runs the formatter you already use, if it's installed. It looks on your login shell's `PATH` plus the
Homebrew, cargo, go and `~/.local` bin folders. Each tool runs in the file's folder, so project configs such as
`.prettierrc`, `rustfmt.toml` and `.clang-format` apply.

| Language | Tool (first one found) |
|---|---|
| JS / TS / TSX / CSS / HTML / Markdown / YAML / JSON | `prettier` |
| JSON (no prettier) | built-in formatter (keeps key order) |
| Go | `gofmt` |
| Rust | `rustfmt` |
| C / C++ | `clang-format` |
| Swift | `swift-format`, or `xcrun swift-format` (Xcode) |
| Python | `ruff`, then `black` |
| TOML / shell / XML | `taplo` / `shfmt` / `xmllint` |

## Requirements

- macOS 26 or later (built and tested on Apple Silicon)
- Xcode 26+ / Swift 6.2+ toolchain to build

## Build & run

```sh
swift build                    # debug build
swift test                     # unit tests
scripts/make-app.sh            # release build → build/Anota.app (ad-hoc signed)
scripts/make-app.sh debug      # debug build → build/Anota.app
open build/Anota.app
```

You can also open `Package.swift` in Xcode and run the `Anota` scheme.

To open files or a folder from the terminal:

```sh
open -a build/Anota.app path/to/folder path/to/file.json
```

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New / Open / Close tab | ⌘N / ⌘O / ⌘W |
| Save / Save As / Save All | ⌘S / ⇧⌘S / ⌥⌘S |
| Find / Find and Replace | ⌘F / ⌥⌘F |
| Find next / previous / use selection | ⌘G / ⇧⌘G / ⌘E |
| Find in Files | ⇧⌘F |
| Format Document | ⌥⇧F |
| Split editor | ⌘\\ |
| Vertical tabs | ⌥⌘T |
| Word wrap | ⌥Z |
| Cycle view mode (Text / Tree / Preview / Split) | ⇧⌘V |

## Project layout

```
Package.swift
Sources/
  AnotaCore/      logic with no UI (unit-tested): file decoding, highlighting, session store,
                  JSON/INI/plist/YAML/TOML parsing, search, formatter runner
    Queries/      tree-sitter highlight queries (generated)
  Anota/          the app: SwiftUI + AppKit (workspace, editor view, tabs, sidebar, find, viewers)
Tests/
  AnotaCoreTests/
Vendor/
  TreeSitterGrammars/   generated tree-sitter parsers (C), vendored from release tarballs
scripts/
  make-app.sh           build the .app bundle
  vendor-grammars.sh    re-fetch tree-sitter grammars + queries (bump versions there)
```

**Dependencies (SwiftPM):** [swift-markdown](https://github.com/swiftlang/swift-markdown),
[Yams](https://github.com/jpsim/Yams), [TOMLKit](https://github.com/LebJe/TOMLKit), and
[swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter).

The tree-sitter grammars are vendored rather than added as packages. Two reasons:
- SwiftPM clones each package's full git history, which totals hundreds of MB for these grammars.
- Several grammar packages have manifests that leave out their external scanner, so they fail to link.

Don't edit `Vendor/` or `Sources/AnotaCore/Queries/` by hand. Change `scripts/vendor-grammars.sh` and re-run it.

## Data & privacy

- **Session data:** stored locally in `~/Library/Application Support/Anota/Session/`. Delete that folder to start
  with a fresh session.
- **Network:** Anota makes no network requests of its own. A Markdown preview loads remote images only if the
  document links to them, and clicked links open in your browser.
- **Formatters:** these are your own installed tools, run only when you format (or save, with Format on Save on).

## Known limitations

- One window per app
- No LSP, git integration or terminal
- Large files (10 MB+) may be slow: tree-sitter re-parses the whole file on each edit
- YAML / TOML / INI trees are view-only. Only JSON values can be edited in the tree
- Not notarized yet. On first launch, right-click → Open

## Third-party licenses

The vendored tree-sitter grammars are MIT-licensed; see `Vendor/TreeSitterGrammars/LICENSES/`.
