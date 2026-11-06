# 04 · Directory tree — 🟡 partial (v0.4)

Code: `Workspace.swift` (FileNode, `root`), `ContentView.swift` (Sidebar, FileRow, FileContextMenu).

## Done
- [x] Open a folder (⌘O accepts folders, or drop a folder on the app via `open -a`)
- [x] Lazy loading (children are read when a folder expands), folders first, natural sort
- [x] Hidden by default: `.git .DS_Store node_modules .build .swiftpm .hg .svn` (other dotfiles such as `.env` are shown)
- [x] Select a file to open it; context menu Reveal in Finder / Copy Path
- [x] Refresh of loaded folders when the app becomes active; only folders whose modification date changed re-scan
- [x] Background scanning (spinner while loading); `FileNode` observable, `expanded` stored on the node (v0.2.0)
- [x] Clicking a folder's name expands/collapses it — fix for "folder randomly can't expand" (only the chevron used to) (v0.2.0)

- [x] File URL drag providers; drop onto an editor/tab strip to open there or onto an editor edge to split (v0.4)

## Partial / limits
- Native pointer delivery of file drops still needs manual verification; provider encoding and target opening are tested.
- FSEvents updates loaded folders and clean buffers while frontmost.

## Not done
- [x] Live refresh with FSEvents (coalesced recursive events; open files outside the root also watched)
- [x] New File / New Folder, inline rename, Move to Trash (never permanent delete; refuses unsaved affected buffers)
- [ ] Show hidden files toggle
- [x] Filter field shares FuzzyMatcher and workspace file index with Quick Open
- [ ] Verify native file drops end-to-end, including Finder destinations
- [ ] Git status colouring (v1.1)
