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
- [ ] Scroll sync between editor and preview
- [ ] Syntax highlighting inside fenced code blocks in the preview (bundle highlight.js locally, no network)
- [ ] Task-list checkboxes rendering (check what HTMLFormatter emits)
- [ ] Export to HTML / PDF
- [ ] Markdown editing helpers (⌘B bold, ⌘I italic, list continuation on Return)
