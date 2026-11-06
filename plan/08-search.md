# 08 · Find, replace, find in files — 🟡 partial

Code: `Sources/AnotaCore/Search.swift`, `Sources/Anota/Find.swift`, menu items in `AnotaApp.swift`.

## Done
- [x] In-file find bar (⌘F, replace ⌥⌘F): floating glass panel, Match Case / Whole Word / Regex / Preserve Case,
      "n of m", invalid-regex indicator, ⌘G / ⇧⌘G, ⌘E use selection, Esc closes, seeded from the selection
- [x] All matches highlighted (temporary attributes, also in split views of the same file)
- [x] Replace / Replace All (Replace All = one undo step); regex `$1` templates
- [x] Find in Files (⇧⌘F, sidebar Search tab): same toggles, include/exclude globs (comma-separated), default excludes
      (`.git node_modules .build build dist *.min.js`), bounded background worker + cancellable + debounced, skips binary and >5MB files
- [x] Results grouped by file with line numbers and highlighted match; click opens and selects the match
- [x] Inline replace preview (old struck through + new), Replace All with confirmation; open buffers changed in place
      (undoable, left unsaved), closed files rewritten on disk keeping encoding/line endings
- [x] Unit tests: options, preserve case, regex templates, globs, folder search

- [x] Search deadlines, bounded snippets, truncation reporting and symlink escape prevention
- [x] Replacement previews and applied edits share regex captures; coordinated disk writes check revisions

## Partial / limits
- Highlights capped at 10K matches; project search stops at 5K matches.
- Replace preview is inline per line, not a per-file diff view.
- Result groups are always expanded; long lines truncated (match may be cut off at the far right).
- Glob semantics are simplified (`fnmatch`, name match when no `/`); `**` only as a prefix.

## Not done
- [ ] Find in selection
- [ ] Respect `.gitignore`
- [ ] Replace in a single file / dismiss a single result from the results list
- [ ] Search history in the fields
- [x] Multi-line find/replace and project search input (vertical fields, up to five visible lines)
