# 03 · Tabs, vertical tabs, split workspace — 🟡 partial (v0.4)

Code: `Sources/Anota/ContentView.swift`, `Workspace.swift`, `PaneLayoutView.swift`, `WorkspaceFileDrop.swift`,
`Sources/AnotaCore/PaneLayout.swift`.

## Done
- [x] Horizontal tabs and grouped vertical sidebar tabs; new-tab button and double-click empty strip
- [x] Close, Close Others, Close Left/Right, Close All, reopen closed tab; dirty-tab confirmation
- [x] Shared buffers across panes; focused-pane indicator; empty-pane removal
- [x] Split left/right/top/bottom from toolbar and tab menu; ⌘\ right, ⌥⌘\ below
- [x] Nested horizontal/vertical layouts, draggable dividers, persisted layout IDs/orientations/ratios
- [x] Tab edge dragging with destination preview; move into another pane's center or tab strip on release
- [x] Cancel drag state safely; clean geometry on actual tab/pane removal rather than view disappearance
- [x] Directory-tree file drops into existing panes/tab strips or new edge splits
- [x] Finder Open With updates the existing window's active tab/editor
- [x] Active file follows tree highlight; tab cycling and ⌘1–3 group focus
- [x] Regression tests for all directions, last-tab moves, cancellation, hosted pane collapse, and session migration

## Partial / limits
- Native UI verified mixed nested splits and tab selection after closing a pane.
- Actual pointer smoothness and native file-drop delivery remain unverified: CUA returned `noWindowsAvailable`.
- Vertical sidebar reorder remains within a group; moving to another pane uses its editor area.
- Dragging the only tab to its own pane edge shares the buffer in both views.

## Not done
- [ ] Manual verification of edge dragging, cross-pane moves and directory-tree file drops
- [x] Pin tab (persisted; protected from bulk close; explicit close still works)
- [x] Close Saved (keeps dirty and pinned tabs)
- [ ] Preview tab (temporary tab on tree single-click)
