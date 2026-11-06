# 10 · Polish & release — 🟡 partially done

## Done
- [x] `scripts/make-app.sh [debug]` → `build/Anota.app` (Info.plist, document types for text, ad-hoc codesign)
- [x] "Open With → Anota" handled (SwiftUI `.onOpenURL`, updates the existing window)
- [x] App icon: `scripts/make-icon.swift` → `assets/AppIcon.icns`, bundled by make-app.sh (about panel uses it)
- [x] Versioning: `.version`, `.changelog`, `scripts/release-tag.sh`, `scripts/release-notes.sh`
- [x] GitHub Actions CI/CD: test + build on push/PR; release (or `-rc-<datetime>` pre-release) on main

- [x] v0.4 version/changelog/README refresh; plan added to version control

## Not done
- [ ] Quick Open ⌘P: fuzzy file finder over the workspace (reuse FileSearch's walker + excludes; share the matcher with the tree filter)
- [ ] Settings window (SwiftUI `Settings` scene): font family/size, tab width, spaces vs tabs, wrap default, theme
- [ ] Release signing with Developer ID + notarization + DMG
- [ ] Reopen recent folders/files menu (NSDocumentController recent items)
- [ ] Crash-free check under large files (10MB log, 50K-node JSON) and performance fixes from 02/07
