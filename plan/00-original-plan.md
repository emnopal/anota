# Anota — Plan

A fast, simple macOS code editor: the speed and range of Notepad++, the calm of Zed,
and the look of a native Mac app.

Toolchain on this machine: Xcode 27.1, Swift 6.4, macOS 27.2 (Apple Silicon).

---

## 1. Goals and non-goals

**v1 must do (what you asked for)**
- Text/code editor with syntax highlighting, line numbers, and current-line highlight
- Tabs, with a **horizontal or vertical** layout toggle
- Directory tree sidebar (open a folder as a workspace)
- Split view (2+ editor groups side by side, each with its own tabs)
- **Hot exit**: quitting with unsaved edits never asks. Every buffer, saved or not, comes back on next launch
- Markdown: editor with live preview (side-by-side or preview-only)
- JSON viewer/editor in the style of Firefox: a collapsible tree, a raw view, a pretty-printed view, a filter box, and copy-path
- Viewers/editors for YAML, TOML and config files (.ini, .conf, .env, .properties, .plist), using the same tree UI
- Advanced search in the style of VS Code: find/replace in the file (regex, case, whole word, in selection, preserve case) and find/replace across files (include/exclude globs, a results tree, a preview before replace-all)

**Non-goals for v1** (add later if needed)
- LSP / autocomplete / go-to-definition
- Git integration, terminal, extensions/plugins
- Multi-cursor (maybe in v1.1, since NSTextView supports multiple selections natively)
- Mac App Store / sandboxing (see Decision C)

---

## 2. Architecture

```
SwiftUI app shell  (window, sidebar, toolbar, tabs, panels, viewers)
        │
        ├── Workspace (@Observable)   one per window
        │     ├── rootFolder: URL?
        │     ├── buffers: [Buffer]          every open file / untitled doc
        │     ├── groups: [EditorGroup]      split panes; each has tabs + active tab
        │     └── tabLayout: .horizontal | .vertical
        │
        ├── Buffer (@Observable)
        │     url?, text storage, encoding, lineEnding, isDirty,
        │     fileType (detected from extension and content), viewMode (.text | .preview | .split | .tree)
        │
        ├── EditorView   NSViewRepresentable around an NSTextView (TextKit 2)
        │                (SwiftUI TextEditor can't do gutters, highlighting at scale, or find bars)
        │
        ├── SessionStore      hot exit: Application Support/Anota/Session/
        ├── StructuredDoc     JSON/YAML/TOML/INI/plist → one shared `Node` tree
        ├── MarkdownRenderer  swift-markdown → HTML → WKWebView
        └── SearchEngine      NSRegularExpression; in-file + across files
```

The key consolidation: **there is one tree viewer for every structured format.** Each parser
turns its format into the same tree, and the viewer only knows that tree:

```swift
indirect enum Node { case object([(key: String, value: Node)])   // keeps key order
                     case array([Node]), string(String), number(String),
                          bool(Bool), null, date(Date) }
```

JSON, YAML, TOML, INI/.env/.properties and plist all feed this one viewer, which provides the
Firefox-style features: disclosure, filter, copy path, copy value, expand/collapse all.

### Dependencies (Swift Package Manager)

| Need | Choice | Why not build it |
|---|---|---|
| Editor view: line numbers, highlighting, find | **CodeEditSourceEditor** (CodeEdit team, MIT) *or* our own NSTextView + **SwiftTreeSitter/Neon** | See Decision A |
| Markdown → HTML | **apple/swift-markdown** (has `HTMLFormatter`) | Apple's CommonMark/GFM parser. `AttributedString(markdown:)` can't render tables or blocks |
| YAML | **Yams** (libyaml) | A YAML parser is large and full of edge cases |
| TOML | **TOMLKit** (toml++) | Same reason |
| JSON | Our own small ordered parser (~150 LOC) | `JSONSerialization` loses key order, and the Firefox-style view needs that order. It also gives source ranges for click-to-jump |
| INI / .env / .properties | Our own (~60 LOC) | Simple line-based formats |
| plist | `PropertyListSerialization` | Built in (stdlib) |

---

## 3. Feature design

### Editor
- NSTextView on TextKit 2. Highlighting runs only on the visible range and the edited range, so large files stay responsive
- A gutter showing line numbers, a current-line highlight, matching-bracket highlight, and word wrap toggle (⌥Z)
- Status bar: line:col, selection count, encoding (UTF-8 / UTF-16 / Latin-1; detected on open, convertible), line endings (LF/CRLF, convertible), language picker, indent (tabs/spaces, width)
- When a file changes on disk: a clean buffer reloads silently, a dirty buffer shows a "file changed on disk" banner (Keep mine / Reload / Compare)

### Tabs
- Each tab shows a file icon (by type) and its name. The close button appears on hover. A dirty tab shows a dot in place of the close button
- Tabs can be dragged to reorder, dragged to another group, or dragged to an edge to create a split
- Pin tab, Close others, Close to the right, and Reveal in tree
- **Vertical tabs**: View ▸ Tab Layout ▸ Vertical. Tabs become a list in the sidebar above the file tree (like Arc or Edge). The setting is per window and persisted
- Preview tab: single-clicking in the tree opens an italic tab that is replaced on the next click; editing it or double-clicking makes it permanent (as in VS Code)

### Directory tree
- A `List` with lazy children (folders load when expanded). FSEvents keeps it updated live
- Supports new file/folder, rename (inline), move to Trash (never a permanent delete), reveal in Finder, and copy path
- Default hidden: `.git`, `node_modules`, `.DS_Store`. A toggle shows hidden files

### Split view
- Editor groups sit in an `HSplitView`/`VSplitView`. ⌘\ splits right, ⌘⌥\ splits down
- The same buffer can be open in two groups, with both views editing one shared text storage
- Markdown "split" mode uses this too: the text sits on the left with a live preview on the right and synced scrolling

### Hot exit / session restore
- Every edit is saved to `~/Library/Application Support/Anota/Session/` after a 1 s debounce, using atomic writes:
  `session.json` (windows, folder, groups, tabs, cursor/scroll per tab, layout) and `buffers/<uuid>.txt` for dirty and untitled content
- Quit (⌘Q) never prompts. On launch, everything is restored exactly as it was, including unsaved and untitled buffers
- Because the session is written continuously, a crash or force-quit loses at most ~1 s of typing
- If a restored dirty buffer's file changed on disk while the app was closed, it uses the same banner as above. **The file on disk is never silently overwritten**
- Session data for a buffer is deleted once that buffer is saved or closed with "Don't Save"

### Markdown
- Modes: Edit, Split (live preview), and Preview. Toggle with ⌘⇧V
- Rendered with swift-markdown → HTML in a WKWebView, using GitHub-like CSS for light and dark. Supports tables, task lists and fenced code with highlighting (highlight.js bundled locally, no network)
- Relative images and links resolve against the file's folder. Clicking a link opens it in the default browser

### JSON / YAML / TOML / config viewer-editor
- Tabs in the style of Firefox's JSON viewer: **Tree | Raw | Pretty**, plus a filter field and buttons for Collapse all, Expand all and Copy
- Tree rows show key, value (colored by type) and a child count. Right-click offers Copy value, Copy path (`$.a.b[2]` for JSON; dotted paths for others), and Jump to source
- Parse errors show inline with line:col, and the Tree tab falls back to the error message
- **Editing**:
  - The Raw tab is the normal text editor for every format, with validation as you type
  - The Tree tab can edit values inline for **JSON** (v1). The edit is applied as a text patch at the node's source range, so formatting is preserved
  - For YAML/TOML/config, the tree is read-only in v1. Re-serializing these formats would destroy comments and layout. Inline tree editing for them is a v1.1 item that needs source-range support from the parsers
- Pretty-printing: Format document (⌥⇧F) for JSON; minify for JSON

### Advanced search
- **In-file bar** (⌘F / ⌥⌘F): find and replace fields with toggles for Aa (case), ab (whole word), .* (regex), in selection, and preserve case. Shows a "3 of 41" count with all matches highlighted. Supports Replace and Replace All (one undo step), and regex capture groups `$1`
- **Find in files** (⌘⇧F) is a sidebar panel with:
  - query and replace fields with the same toggles, plus "files to include" and "files to exclude" globs
  - search running concurrently over the workspace (`TaskGroup`, cancellable as you type), skipping binary files and the default excludes
  - results grouped by file, with each matching line highlighted. Clicking a result opens the file at that match
  - Replace All showing a preview diff per file before applying. Applied replacements go through open buffers where they exist, so they are undoable and don't race with unsaved edits
- **Filter**: the file tree has a filter field for fuzzy name matching. Quick Open (⌘P) uses the same fuzzy matcher

---

## 4. Visual / UX direction ("feels like a Mac app")
- `NavigationSplitView`: sidebar (tree / search / vertical tabs) + detail (editor groups). Unified toolbar with the title, path breadcrumb and a few icons
- macOS 26+ Liquid Glass materials on the sidebar and toolbar. SF Symbols only. Follows the system accent color and light/dark appearance
- Typography: SF Mono (user can change the font and size). Generous line height, a quiet gutter and thin separators
- Two built-in themes (light and dark) chosen for contrast, plus following the system appearance. No theme marketplace in v1
- A minimal chrome: by default nothing beyond the sidebar, tabs, editor and status bar. Panels appear when invoked
- Keyboard-first: everything has a shortcut and a menu item (menus double as discoverability). A command palette (⇧⌘P) is planned for v1.1
- Accessibility: VoiceOver labels on tabs/tree/toolbar, Dynamic Type for UI chrome, Reduce Motion respected

---

## 5. Project layout

SPM-based, so it builds and tests from the CLI (`swift build`, `swift test`) and opens in Xcode.

```
anota/
  Package.swift
  Sources/Anota/
    App/          AnotaApp.swift, Commands.swift (menus/shortcuts)
    Workspace/    Workspace.swift, Buffer.swift, EditorGroup.swift, SessionStore.swift
    Editor/       EditorView.swift (NSTextView bridge), FindBar.swift, StatusBar.swift
    Sidebar/      FileTree.swift, TabList.swift (vertical), SearchPanel.swift
    Tabs/         TabBar.swift
    Viewers/      MarkdownPreview.swift, TreeViewer.swift, Node.swift,
                  JSONParser.swift, INIParser.swift, StructuredLoaders.swift (YAML/TOML/plist → Node)
    Search/       SearchEngine.swift
    Resources/    markdown.css, highlight.min.js
  Tests/AnotaTests/
    JSONParserTests, INIParserTests, SearchEngineTests, SessionStoreTests
  scripts/make-app.sh   builds a release .app bundle (Info.plist, icon, codesign ad-hoc)
```

Tests cover the parts with logic: parsers (key order, ranges, errors), search/replace (regex, whole word, preserve case, captures), and the session round-trip (dirty + untitled buffers survive). UI is checked by running the app.

---

## 6. Milestones

| # | Milestone | Done when |
|---|---|---|
| 0 | Skeleton | App launches, opens/saves a file, shows one editor with highlighting and line numbers |
| 1 | Editor core | In-file find/replace bar, status bar, encoding and line-ending handling, word wrap, external-change banner |
| 2 | Workspace | Folder tree, tabs (horizontal and vertical), split groups, drag tabs between groups |
| 3 | Hot exit | Quit with dirty and untitled buffers, relaunch, and everything is back. A kill -9 test loses ≤1 s of edits |
| 4 | Markdown | Edit / Split / Preview with live update, scroll sync, local images, dark mode |
| 5 | Structured | JSON tree/raw/pretty with filter, copy path and inline edit. YAML/TOML/INI/.env/plist in the tree view |
| 6 | Find in files | Panel with globs, results tree, preview + undoable replace-all |
| 7 | Polish | Quick Open (⌘P), settings (font, theme, tab size), app icon, `make-app.sh` |

Each milestone ends with a runnable app and passing `swift test`.

---

## 7. Decisions to confirm (defaults are in bold)

- **A. Editor engine**
  - **CodeEditSourceEditor** gives us gutter, tree-sitter highlighting for many languages, and a minimap out of the box. It saves weeks, but it's a large dependency whose API has to be learned
  - The alternative is our own NSTextView + SwiftTreeSitter: full control, but more code for the gutter and highlighting
  - Default: **CodeEditSourceEditor**, falling back to our own view if it gets in the way of split view or hot exit
- **B. Minimum macOS**: **macOS 26** (Liquid Glass, modern SwiftUI and Observation). Older versions would mean extra fallback code
- **C. Distribution**: **direct (non-sandboxed, notarized later)**. An editor needs to open arbitrary files and folders and restore them freely. The App Store sandbox would require security-scoped bookmarks for every restored file and folder. This is doable, but it adds complexity and failure modes
- **D. App name**: **Anota** (from the folder name)
