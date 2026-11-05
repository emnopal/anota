<p align="center"><img src="assets/AppIcon.png" width="128" alt="Anota icon"></p>

<h1 align="center">Anota</h1>

A simple, fast code editor for macOS.
Written in Swift (SwiftUI + AppKit).

> Status: **v0.2.0**. Core features work and are unit-tested. See [`.changelog`](.changelog).

## Features

- **Editor:** syntax highlighting (tree-sitter for 14 languages, regex for the rest; incremental, so long files stay responsive), line numbers,
  current-line highlight, auto-indent, word wrap (toolbar, View menu, right-click or ⌥Z), and per-file undo
- **Encodings and line endings:** UTF-8 / UTF-8 BOM / UTF-16 / Latin-1 detection, LF / CRLF / CR,
  convertible from the status bar
- **Tabs:** horizontal, or vertical in a pinned "Tabs" sidebar section (⌥⌘T). Drag to reorder or to move between
  panes. Close Others / Close Tabs to the Left / to the Right / Close All. New file: the tab bar's + button or
  double-click its empty area
- **Split view (⌘\\):** panes share the width equally, with draggable dividers. The same file in two panes is edited
  live in both
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
- **Formatting:** Format Document (⌥⇧F), Format Selection (⌥⇧⌘F) and an optional Format on Save, using the
  standard tool for each language (see below). Also in the toolbar and the editor's right-click menu
- **External changes:** files changed on disk reload. If you also have unsaved edits, Anota asks which version to keep

### Syntax highlighting

| Engine | Languages |
|---|---|
| tree-sitter | JSON/JSONC, YAML, TOML, INI/.properties, Python, JavaScript/JSX, TypeScript, TSX, Go, C, C++, Rust, Swift, Bash/Zsh |
| regex | Markdown, HTML/XML, CSS, Java/Kotlin, Ruby, SQL, .env, log files (levels, timestamps, IPs, stack frames), Batch (.bat/.cmd), PowerShell (.ps1) |

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

## Install

Download `Anota-<version>-macos-arm64.dmg` from [Releases](https://github.com/emnopal/anota/releases), open it, and
drag `Anota.app` to Applications. Builds are **arm64 (Apple Silicon)** only; Intel Macs can build from source. The app is ad-hoc signed, not notarized: on first launch right-click → Open, or run
`xattr -dr com.apple.quarantine /Applications/Anota.app`.

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
| New / Open / Close tab (or empty pane) / Close all tabs | ⌘N / ⌘O / ⌘W / ⌥⌘W |
| Save / Save As / Save All | ⌘S / ⇧⌘S / ⌥⌘S |
| Find / Find and Replace | ⌘F / ⌥⌘F |
| Find next / previous / use selection | ⌘G / ⇧⌘G / ⌘E |
| Find in Files | ⇧⌘F |
| Format Document / Format Selection | ⌥⇧F / ⌥⇧⌘F |
| Split editor | ⌘\\ |
| Vertical tabs | ⌥⌘T |
| Word wrap | ⌥Z |
| Cycle view mode (Text / Tree / Preview / Split) | ⇧⌘V |

VS Code shortcuts (macOS bindings):

| Action | Shortcut |
|---|---|
| Toggle line comment | ⌘/ |
| Move line up / down | ⌥↑ / ⌥↓ |
| Copy line up / down | ⇧⌥↑ / ⇧⌥↓ |
| Delete line | ⇧⌘K |
| Insert line below / above | ⌘↩ / ⇧⌘↩ |
| Indent / outdent line | ⌘] / ⌘[ |
| Expand line selection | ⌘L |
| Select next occurrence (single selection) | ⌘D |
| Go to line[:column] | ⌃G |
| Next / previous tab | ⌃⇥ / ⌃⇧⇥, ⌥⌘→ / ⌥⌘← |
| Focus editor group 1–3 (one past the last splits) | ⌘1 / ⌘2 / ⌘3 |
| Reopen closed tab | ⇧⌘T |
| Toggle sidebar / show Explorer | ⌘B / ⇧⌘E |
| Find in files, format, replace, word wrap, split | ⇧⌘F, ⌥⇧F, ⌥⌘F, ⌥Z, ⌘\\ (as above) |

Not yet: Quick Open (⌘P), Command Palette (⇧⌘P), multi-cursor, and two-key chords (⌘K …).

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
  make-icon.swift       render assets/AppIcon.icns
  release-tag.sh        next release tag from .version
  release-notes.sh      the .changelog section for .version
assets/                 app icon
.github/workflows/      CI: test, build, release
  vendor-grammars.sh    re-fetch tree-sitter grammars + queries (bump versions there)
```

**Dependencies (SwiftPM):** [swift-markdown](https://github.com/swiftlang/swift-markdown),
[Yams](https://github.com/jpsim/Yams), [TOMLKit](https://github.com/LebJe/TOMLKit), and
[swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter).

The tree-sitter grammars are vendored rather than added as packages. Two reasons:
- SwiftPM clones each package's full git history, which totals hundreds of MB for these grammars.
- Several grammar packages have manifests that leave out their external scanner, so they fail to link.

Don't edit `Vendor/` or `Sources/AnotaCore/Queries/` by hand. Change `scripts/vendor-grammars.sh` and re-run it.

## Versioning & releases

- `.version` holds the version (`0.2.0`). It sets the app's version; the build number is the commit count.
- `.changelog` has a `## v<version>` section per release; that section becomes the release notes.
- CI (`.github/workflows/ci.yml`) runs `swift test` and `scripts/make-app.sh` on every push and pull request.
  When both pass on `main`, it publishes a GitHub release with the zipped app:
  - `.version` changed (no `v<version>` tag yet) → release **`v<version>`**
  - `.version` unchanged → pre-release **`v<version>-rc-<UTC YYYYMMDDHHMMSS>`**, e.g. `v0.2.0-rc-20261030101010`
- To release a new version: bump `.version`, add its section to `.changelog`, push to `main`.

## Data & privacy

- **Session data:** stored locally in `~/Library/Application Support/Anota/Session/`. Delete that folder to start
  with a fresh session.
- **Network:** Anota makes no network requests of its own. A Markdown preview loads remote images only if the
  document links to them, and clicked links open in your browser.
- **Formatters:** these are your own installed tools, run only when you format (or save, with Format on Save on).

## Known limitations

- One window per app
- No LSP, git integration or terminal
- Very large files (several MB): colours of the edited line update after a short pause in typing
- YAML / TOML / INI trees are view-only. Only JSON values can be edited in the tree
- Not notarized yet. On first launch, right-click → Open

## Third-party licenses

The vendored tree-sitter grammars are MIT-licensed; see `Vendor/TreeSitterGrammars/LICENSES/`.
