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
- [x] ⇧⌘T reopen closed tab; ⌘B toggle sidebar; ⇧⌘E show Explorer
- [x] Already VS Code-compatible before: ⌘F, ⌥⌘F, ⇧⌘F, ⌥⇧F, ⌥Z, ⌘\\, ⌘W, ⌘N

## ⬜ Not done
- [ ] **Multi-cursor — to consider later (user decision pending).** Moderate feature, more work than all the shortcuts above together.
  - NSTextView already stores several selections (`selectedRanges`), but typing/deleting/arrow keys only act on one.
  - Plan: in `CodeTextView` override `insertText`, `deleteBackward`/`deleteForward`, `insertNewline`, paste and the
    `move*` / `move*AndModifySelection` actions to apply per range, back to front, inside one undo group
    (`undoManager.beginUndoGrouping`); draw secondary carets (NSTextView draws only the first insertion point);
    Esc collapses to one cursor.
  - Shortcuts: ⌘D add next occurrence as a cursor, ⇧⌘L all occurrences, ⌥-click add cursor, ⌥⌘↑/↓ cursor above/below.
  - Edge cases: overlapping ranges after edits (merge), auto-indent per cursor, Find bar and format discard extra cursors.
- [ ] Quick Open ⌘P (see 10), Command Palette ⇧⌘P
- [ ] Two-key chords (⌘K ⌘W, ⌘K ⌘F, …): SwiftUI menus can't express them; needs an NSEvent monitor
- [ ] User-configurable keybindings

## Verify
`swift test` (`lineEdits`). Manual: each Selection/Go menu item with the caret in the editor; undo after each.
