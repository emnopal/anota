# Requested feature pass — 6 November 2026

Implemented the requested items from `plan/01` through `plan/11`. Duplicate requests (multi-window, font settings, multi-cursor) share one implementation. No release was published and no installed app was replaced.

| Requests | Result |
| --- | --- |
| 1, 30 | WindowGroup, independent Workspace/session directories, focused-scene commands; window manifest restores windows; dirty closed-window checkpoints stay discoverable; old single-window session migrates once |
| 2 | Matching bracket underline, mixed nesting, bounded 100K-character scan |
| 3 | Global tabs/spaces and width, native tab stops, Tab/Backtab, indentation detection and document override |
| 4 | Reopen with explicit encoding, dirty-buffer discard/cancel, UTF-16 endianness, retained decoding on reload/session restore |
| 5, 31 | Native multiple ranges, Cmd-D, cursor above/below, typing, backward/forward deletion, newline and undo; native Option-drag column selection |
| 6, 22, 25 | SwiftUI Settings scene; family/size/indent/wrap defaults; System, Light, Dark, Solarized and Midnight; custom gutter background and scaled gutter font |
| 7, 13, 21 | Edge split and cross-pane tab move observed; themes/fonts reviewed; OS-native file drops remain unverified, see below |
| 8, 9 | Pin/unpin and persisted pin state; bulk closes protect pins; Close Saved keeps dirty/pinned documents |
| 10 | Recursive coalesced FSEvents, including parents of files outside the workspace; clean reload and dirty conflict handling |
| 11 | New file/folder, focused inline rename, open-buffer URL updates, Move to Trash only; affected unsaved buffers block Trash |
| 12, 24 | Shared FileSearch walker/default excludes and FuzzyMatcher; indexed tree filter and Quick Open, keyboard selection |
| 14 | Session stores view mode, proportional editor scroll, preview scroll, pin and explicit read encoding; optional keys migrate old sessions |
| 15 | Bidirectional proportional editor/preview scroll sync |
| 16, 17 | Locally bundled highlight.js 11.11.1, BSD license included; JavaScriptCore renders code spans; safe renderer uses ListItem.checkbox; web content JS remains disabled |
| 18 | HTML and continuous-page PDF export from File menu; WebKit PDF output tested with PDFKit |
| 19 | Cmd-B/Cmd-I Markdown wrappers; ordered/unordered/task list continuation, unchecked next task, empty-item termination |
| 20 | Vertical multi-line find/replace/project-search fields, five visible lines |
| 23 | Shift-Cmd-P command palette, shared fuzzy matcher |
| 26 | Build/sign/notarize/staple/DMG scripts added; Developer ID signing/notarization skipped at user request |
| 27 | NSDocumentController recent files/folders and clear menu |
| 28 | Release tests open/index/edit a 10MB log and parse/build a tree for a 50K-object JSON array |
| 29 | User-configured stdio LSP server; initialize/open/change/close, completion (Ctrl-Space), definition (Go menu/palette), diagnostic backgrounds/tooltips; UTF-16 positions, framed bytes, timeouts |

## Verification

- Release Swift Testing suite: **42 app tests and 90 core tests passed**, with `ANOTA_BENCHMARK=1 ANOTA_REAL_LSP=1`. Includes completion against installed SourceKit-LSP, mock-server definition/diagnostics, actual FSEvents refresh, real create/rename/Trash and restoration, PDF text extraction, 10MB log and 50K-object JSON.
- External Open With uses SwiftUI scene preferences and a single onOpenURL owner. Native Finder → Open With → Other was checked against the current isolated build: one existing window stayed one; with two windows the most recently active window received the file and the count stayed two; after closing workspace windows, one file window appeared. The Window menu showed no empty companion. The obsolete custom-router unit test was removed with that router.
- Separate-process crash recovery passed: a disposable test runner was killed after checkpointing; a fresh process restored its dirty buffer.
- Native observations: independent second window; quit/relaunch restoration; right-edge tab split; cross-pane tab move and empty-pane collapse; successive multi-cursor typing with visible carets; Quick Open matching and relative paths; local Markdown image/tasks/code highlighting; Dark, Light, Solarized and Midnight appearances; live font family/size changes; large log and JSON text opening without a crash. Original main-app font/theme preferences were restored.
- Verification found and fixed successive multi-cursor typing losing empty selections, horizontal ruler baseline clipping, temporary-directory relative paths, main-thread FSEvents startup blocking, and SwiftUI skipping Markdown scroll-sync updates. Hosted WebKit regression exercises scroll synchronization in both directions.
- Native file-drop automation remains inconclusive: the same drag was a no-op in Finder's own baseline test. Tree-to-pane drops, Finder destinations and Option-drag column selection need human verification. No pass is claimed for all edge permutations, divider dragging, JSON's native tree-mode switch, or exported PDF visual layout.
- Grid benchmark and main-actor heartbeat ran enabled. These are local measurements, not a latency guarantee.
- Developer ID signing/notarization skipped as requested; the prior identity check found zero valid signing identities. Local artifacts use an ad-hoc signature.

- Final local artifacts: `build/Anota.app` (ad-hoc signature verified) and `build/Anota-0.4.dmg` (hdiutil checksum verified). Nothing published or installed over the existing app.

## Practical limits

- Bracket scanning is bounded and structural; it does not lexically exclude strings/comments.
- Multi-selection typing/deleting/newlines work together; auto-pairing and line-transform helpers are single-selection operations. Native Option-drag delivery still needs a human check.
- Scroll sync is proportional, not source-line anchored. HTML export retains relative image paths; copy those assets alongside an exported HTML document. PDF is a continuous page.
- Quick Open/tree-filter results cap at 200; workspace indexing caps at 100K files and respects FileSearch's existing excludes, not .gitignore.
- LSP is one explicitly configured installed server per workspace. It uses full-document updates under two million characters, plain completion text, and supports no snippets, server installation, workspace edits, or arbitrary server-initiated requests. Process recovery remains opt-in and was run separately; per-window filesystem restore tests run normally.

## Remaining manual checks

1. Check dirty closed-window recovery in the native UI; external Open With routing was checked directly in Finder.
2. Drag first/middle/last tabs to all four pane edges and other pane centers/strips; cancel midway; verify last-tab pane collapse and split-divider dragging.
3. Drag tree files into centers/edges/strips, then into a disposable Finder folder; verify actual copied file contents.
4. Check long tab titles, narrow panes and dark-mode find controls; themes and font changes were visually observed.
5. Option-drag a column, type/delete/undo, and use Cmd-D repeatedly, including wrapping at EOF.
6. Check local Markdown images, scroll sync around long code blocks/images, exported relative assets and PDF appearance.
