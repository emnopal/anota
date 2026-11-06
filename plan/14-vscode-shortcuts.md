# 14 · VS Code shortcuts & multi-cursor — 🟡 partially done

Code: `Sources/Anota/AnotaApp.swift` (Selection / Go menus, `AppCommands.line`), `Sources/Anota/EditorView.swift`
(`CodeTextView` line commands), `Sources/AnotaCore/LineEdits.swift` (pure logic + `Language.lineComment`, tested),
`Sources/Anota/Workspace.swift` (`goToLine`, `cycleTab`, `focusGroup`, `reopenClosed`, `sidebarVisible`).
Menu items send their selector down the responder chain (`NSApp.sendAction(_, to: nil)`), so they act on the focused editor.

## ✅ Done (v0.2.0)
- [x] ⌘/ toggle line comment (per-language marker; block-only languages wrap with `<!-- -->` / `/* */`)
- [x] ⌥↑/⌥↓ move line(s), ⇧⌥↑/⇧⌥↓ copy line(s), ⇧⌘K delete line(s)
- [x] ⌘↩ / ⇧⌘↩ insert line below / above (keeps indent), ⌘] / ⌘[ indent / outdent
- [x] ⌘L expand line selection, ⌘D select word → next occurrence (**single selection**)
- [x] ⌃G go to line[:column]; ⌃Tab / ⌃⇧Tab and ⌥⌘→ / ⌥⌘← cycle tabs; ⌘1–⌘3 focus pane (one past the end splits)
- [x] ⇧⌘T reopen closed tab; ⌃⌘B toggle sidebar (⌘B is Markdown bold); ⇧⌘E show Explorer
- [x] Already VS Code-compatible before: ⌘F, ⌥⌘F, ⇧⌘F, ⌥⇧F, ⌥Z, ⌘\\, ⌘W, ⌘N

## ⬜ Not done
- [x] Native multiple selections, Cmd-D, add cursors above/below, column selection; typing/deleting/newlines are undoable. Pairing and line transforms remain single-selection helpers.

- [x] Quick Open ⌘P (see 10), Command Palette ⇧⌘P
- [ ] Two-key chords (⌘K ⌘W, ⌘K ⌘F, …): SwiftUI menus can't express them; needs an NSEvent monitor
- [ ] User-configurable keybindings

## Verify
`swift test` (`lineEdits`). Manual: each Selection/Go menu item with the caret in the editor; undo after each.
