# 10 · Polish & release — 🟡 partially done

## Done
- [x] `scripts/make-app.sh [debug]` → `build/Anota.app` (Info.plist, document types for text, ad-hoc codesign)
- [x] "Open With → Anota" handled (SwiftUI `.onOpenURL`, updates the existing window)
- [x] App icon: `scripts/make-icon.swift` → `assets/AppIcon.icns`, bundled by make-app.sh (about panel uses it)
- [x] Versioning: `.version`, `.changelog`, `scripts/release-tag.sh`, `scripts/release-notes.sh`
- [x] GitHub Actions CI/CD: test + build on push/PR; release (or `-rc-<datetime>` pre-release) on main

- [x] v0.4 version/changelog/README refresh; plan added to version control

## Not done
- [x] Quick Open ⌘P: shared FileSearch walker/excludes, index and FuzzyMatcher; keyboard navigation
- [x] SwiftUI Settings scene: font family/size, tab width, spaces/tabs, wrap default, theme, LSP command
- [ ] Release signing with Developer ID + notarization + DMG
- [x] Reopen recent folders/files via NSDocumentController recent items
- [x] Release-mode regression checks: 10MB log indexing/edit and 50K-object JSON parse/tree construction
