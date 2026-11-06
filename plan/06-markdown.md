# 06 · Markdown editor & viewer — 🟡 partial

Code: `Sources/AnotaCore/Formats.swift` (`MarkdownHTML`), `Sources/Anota/MarkdownPreview.swift`, mode switching in `ContentView.swift` / `Buffer.modes`.

## Done
- [x] Modes Text / Split / Preview (toolbar segmented picker, ⇧⌘V cycles)
- [x] swift-markdown AST → escaped HTML in a WKWebView; tables and strikethrough
- [x] GitHub-like CSS with light/dark; relative local images resolve against the file's folder
- [x] Live update while typing in Split; preview scroll position kept across re-renders
- [x] HTTP/HTTPS/mailto links open externally; unsafe schemes and relative links are not navigated
- [x] Markdown syntax highlighting in the editor (headings, code, links, emphasis, quotes, lists)

- [x] Raw HTML escaped, document JavaScript disabled, CSP blocks remote images/forms; scroll-restoration tests

## Partial / limits
- Re-renders the whole page on each change (fine for normal docs).
- Local images rely on WKWebView allowing file access under the base URL; **not verified** visually.

## Not done
- [x] Bidirectional proportional scroll sync between editor and preview
- [x] Fenced code highlighting using bundled highlight.js 11.11.1 in JavaScriptCore; preview document JavaScript remains disabled
- [x] Disabled checked/unchecked task-list inputs rendered from swift-markdown ListItem.checkbox (custom safe renderer)
- [x] Export to HTML / PDF (PDF uses a continuous document page)
- [x] Markdown helpers: ⌘B bold, ⌘I italic, ordered/unordered/task-list continuation and empty-item termination
