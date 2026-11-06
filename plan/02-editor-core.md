# 02 · Editor core — 🟡 partial (v0.2.0)

Code: `Sources/Anota/EditorView.swift`, `Sources/Anota/Workspace.swift` (Buffer), `Sources/AnotaCore/{Highlighter,TextFile,Language}.swift`.

## Done
- [x] Syntax highlighting: tree-sitter for 14 grammars, regex for the rest (details: 12-syntax-highlighting.md)
- [x] Line-number gutter (current line emphasised), current-line highlight, SF Mono 13pt + 3pt line spacing
- [x] Auto-indent on Return (copies leading whitespace)
- [x] Auto-closing pairs + smart Return/Backspace/outdent (`AnotaCore/AutoPair.swift`, tested). Indent unit 4 spaces
      (tabs kept when the line uses tabs); no per-language pair config; off for plain text, logs and data files
- [x] Word wrap toggle ⌥Z (persisted)
- [x] Encoding detection (UTF-8, UTF-8 BOM, UTF-16 BOM, Latin-1 fallback), binary files rejected with a message
- [x] Line ending detection LF/CRLF/CR; status-bar picker converts on next save
- [x] Status bar: Ln/Col, line ending, encoding, language pickers
- [x] Save / Save As / Save All; "can't encode → save as UTF-8?" prompt instead of losing characters
- [x] Per-buffer undo stack (not the window's shared one)
- [x] Format Document ⌥⇧F + Format on Save (details: 13-formatting.md)
- [x] Programmatic whole-text rewrites (format, Replace All) apply a minimal edit: one undo step, cursor kept
- [x] Long files: incremental tree-sitter, colours as layout-manager temporary attributes (no relayout),
      highlighting in 100K-char slices, debounced re-parse above 300K chars, background first parse (v0.2.0)
- [x] `LineIndex` (AnotaCore): O(log n) line lookups for gutter, caret line, Go to Line (v0.2.0)
- [x] Go to Line ⌃G, toggle comment ⌘/, move/copy/delete line, indent/outdent (see 14-vscode-shortcuts.md)
- [x] External change on app activate: clean buffers reload, dirty ones show a "Keep Mine / Reload" banner

## Partial / limits
- Multi-MB files: an incremental re-parse still costs ~0.1 s, so colours update ~0.25 s after typing pauses.
  The first open of a 5 MB file parses ~0.7 s in the background (text shows uncoloured meanwhile).
- `LineIndex` is rebuilt per edit (one ~4 ms scan per 5 MB); incremental update if it ever shows up in profiles.
- Encoding picker changes the **save** encoding only (no "reopen with encoding").
- Dirty flag stays set after undoing back to the saved state. UTF-8 BOM isn't written back.

## Not done
- [ ] Matching-bracket highlight
- [ ] Indentation settings: tabs vs spaces, width, Tab key inserting spaces, detect from file
- [ ] Reopen with encoding
- [ ] "Compare" button in the conflict banner (diff disk vs mine)
- [ ] Multi-cursor (see 14-vscode-shortcuts.md, to consider later)
- [ ] Font family/size setting (see 10)

## Verify
`swift test` covers highlighter/TextFile. Manual: open CRLF + Latin-1 files, edit, save, `xxd` the result.
