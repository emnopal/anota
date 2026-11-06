# 07 · JSON / YAML / TOML / config viewers & editors — 🟡 partial

Code: `Sources/AnotaCore/{Node,Formats}.swift`, `Sources/Anota/TreeViewer.swift`, `Buffer.parseTree` / `Buffer.modes`.

## Done
- [x] One shared tree (`Node` → `TreeItem`) for every format; Text / Tree mode switch
- [x] JSON: own order-preserving parser with source ranges; tolerates `//` `/* */` comments and trailing commas (JSONC);
      errors with line:column + "Show in Text"
- [x] YAML (Yams compose; key order kept; bool/null/number typing)
- [x] TOML (TOMLKit)
- [x] Config: INI sections, `key = value` / `key: value`, `.env` with `export`, `.properties`, quotes stripped
- [x] XML property lists (`.plist`)
- [x] Firefox-style viewer: filter keys+values (keeps ancestors), Expand All / Collapse All, type-coloured values,
      child counts, Copy Value, Copy Path (`$.a["b c"][0]`), Show in Text
- [x] JSON editing: double-click / "Edit Value…" on a scalar → patched at its source range (formatting kept,
      undoable, rejected if it would make invalid JSON)
- [x] Format Document ⌥⇧F (keeps key order and number text) and Minify JSON
- [x] Text mode is always a fully editable editor with highlighting for each format

## Partial / limits
- YAML / TOML / INI / plist trees are **read-only** (no source ranges; re-serialising would drop comments).
- TOML keys appear **sorted**, not in file order (goes through toml++'s JSON output).
- YAML: first document only; no "Show in Text" (Yams marks are line/col only, not wired).
- Binary plists can't be opened (rejected as binary).
- Tree is a recursive SwiftUI List: very large JSON (≥50K nodes) may be slow.
- No separate "Pretty" tab as in Firefox; Format Document covers it.

## Not done
- [ ] Inline edit for YAML/TOML/INI (needs value source ranges: INI ranges exist per line already; YAML via Mark→offset)
- [ ] Add / delete / rename keys from the tree
- [ ] TOML in file order (own TOML key-order pass or a different parser)
- [ ] "Show in Text" for YAML (convert Mark line/col to offset)
- [ ] Binary plist view (PropertyListSerialization handles binary; needs a Data path, not TextFile)
- [ ] Raw/Pretty/Tree segmented control exactly like Firefox (optional)
- [ ] JSON Schema validation (v1.1)
