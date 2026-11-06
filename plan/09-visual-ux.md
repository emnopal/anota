# 09 · Visual / UX (Mac-native look) — 🟡 partial

Code: mostly `ContentView.swift`, `Theme` in `EditorView.swift`, `FindBar` in `Find.swift`.

## Done
- [x] NavigationSplitView sidebar + unified toolbar (title = file name, subtitle = folder path)
- [x] Toolbar: view-mode segmented picker, tab layout toggle, split button
- [x] Liquid Glass find bar (`.glassEffect`), SF Symbols per file type, system colours (light/dark), accent colour
- [x] Minimal chrome: tabs, editor, slim status bar; empty state with New/Open
- [x] Every action is in the menu bar with a shortcut

## ⚠️ Not verified
- **Nobody has looked at the UI yet.** The agent can't screenshot (no Screen Recording / Accessibility permission).
  First task for the next session: a human runs the app and lists visual issues.

## Not done
- [ ] Visual review pass + fixes (spacing, tab bar height, gutter colours, dark mode check)
- [x] System/Light/Dark/Solarized/Midnight themes; editor font family and size in Settings
- [ ] VoiceOver audit (labels exist on close buttons; tree/tabs not audited); Reduce Motion
- [x] Command palette ⇧⌘P

## v0.4 verification update
Native UI checks covered mixed nested splits and tab selection after pane closure. Hosted-view tests cover actual
pane/tab geometry and resizing. Pointer smoothness, cross-pane mouse drags and native file-drop delivery still need
manual verification; CUA coordinate actions returned `noWindowsAvailable`. Earlier unverified notes remain historical.
