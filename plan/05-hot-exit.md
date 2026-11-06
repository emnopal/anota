# 05 · Session restore / hot exit — ✅ done

Code: `Sources/AnotaCore/Session.swift`, `Workspace.swift` (`scheduleSave`, `saveSession`, `restore`), `AnotaApp.swift` (`applicationShouldTerminate`).

## Done
- [x] Quit saves recovery data; failure offers Retry / Save As / Cancel Quit; restored next launch
- [x] Unsaved and untitled buffers restored with content, encoding, line ending, language, cursor position
- [x] Groups, tabs, active tab, focused group, open folder, vertical-tab and wrap settings restored
- [x] Periodic recovery checkpoints during continuous typing, plus on quit; recovery write failures reported
- [x] Stored at `~/Library/Application Support/Anota/Session/`; buffer files of saved/closed tabs are cleaned up
- [x] Dirty buffer whose file changed on disk while the app was closed → conflict banner (never overwritten silently)
- [x] Verified end-to-end (quit/relaunch with a dirty untitled tab + 2 groups + vertical tabs)

- [x] Coordinated saves compare disk contents before replacement; conflict regression tests

## Limits
- Scroll position and view mode (Tree/Preview) aren't persisted, only the cursor.
- Split orientation and sizes are persisted; legacy side-by-side sessions migrate automatically.
- Single window only.
- Undo history is not persisted (same as most editors).

## Not done
- [ ] Persist view mode + scroll position
