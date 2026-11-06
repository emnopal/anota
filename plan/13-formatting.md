# 13 · Formatting (Format Document / Format on Save) — 🟡 PARTIALLY DONE

Code: `Sources/AnotaCore/CodeFormatter.swift` (tool table, PATH lookup, process runner, `minimalEdit`),
`Workspace.format` / `saveCommand` / `flash`, menu items in `AnotaApp.swift`, status text in `StatusBar`.

## ✅ Done
- [x] **Format Document** ⌥⇧F (Edit menu, also the "Format" button in JSON tree view)
- [x] **Format on Save** toggle (Edit menu, persisted); a failing/missing formatter never blocks the save
- [x] Tool per language (first one installed wins):
      prettier (JS/TS/TSX/CSS/HTML/Markdown/YAML/JSON) · gofmt · rustfmt · clang-format (C/C++) ·
      swift-format → `xcrun swift-format` · ruff → black · taplo (TOML) · shfmt · xmllint (XML/plist);
      built-in JSON formatter when prettier is missing
- [x] Finds tools on the **login shell's PATH** (Finder-launched apps don't get it) + Homebrew/cargo/go/~/.local dirs;
      runs in the file's folder so `.prettierrc`, `rustfmt.toml`, `.clang-format`, … apply
- [x] Safety: result discarded if the buffer was edited meanwhile; 10s timeout; empty output = failure;
      stdin/stdout via temp files (no pipe deadlocks); errors shown in the status bar (hover for full text)
- [x] Result applied as a minimal edit → one ⌘Z undoes it, cursor/scroll stay put
- [x] Tests with fake tools (stdin/stdout, priority, args, stderr, empty output, timeout, missing tool, built-in JSON, minimalEdit)
- [x] Verified with real tools on this Mac: gofmt, rustfmt, ruff, xcrun swift-format, xmllint
      (prettier, clang-format, black, taplo, shfmt not installed here → clear "Install …" message)

## 🟡 Partial / limits
- Save All doesn't format.
- Workspace-local tools (`node_modules/.bin/prettier`) aren't used, only PATH.
- xmllint adds an `<?xml version="1.0"?>` declaration if missing.
- Tools load their project config (e.g. `prettier.config.js` is code) — same trust as running the tool in a terminal.
- Format-on-save UI flow not clicked through by a human yet.

## ⬜ Not done
- [ ] Format Selection
- [ ] Settings: choose tool / extra args per language, format on save per language (needs Settings window, see 10)
- [ ] Use project-local prettier (with a trust prompt)
- [ ] Format on paste / format on type
