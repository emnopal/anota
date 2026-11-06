import AppKit
import SwiftUI
import Observation

@Observable final class EditorSettings {
    static let shared = EditorSettings()
    var fontName = UserDefaults.standard.string(forKey: "editorFont") ?? "Menlo" { didSet { save(fontName, "editorFont") } }
    var fontSize = UserDefaults.standard.double(forKey: "editorSize").nonzeroOr(13) { didSet { save(fontSize, "editorSize") } }
    var tabWidth = max(1, UserDefaults.standard.integer(forKey: "tabWidth").nonzeroOr(4)) { didSet { save(tabWidth, "tabWidth") } }
    var spaces = UserDefaults.standard.object(forKey: "indentSpaces") as? Bool ?? true { didSet { save(spaces, "indentSpaces") } }
    var wrap = UserDefaults.standard.bool(forKey: "wrapDefault") { didSet { save(wrap, "wrapDefault") } }
    var theme = UserDefaults.standard.string(forKey: "editorTheme") ?? "System" { didSet { save(theme, "editorTheme") } }
    var lspCommand = UserDefaults.standard.string(forKey: "lspCommand") ?? "" { didSet { save(lspCommand, "lspCommand") } }
    var unit: String { spaces ? String(repeating: " ", count: min(16, max(1, tabWidth))) : "\t" }
    private func save(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
}
private extension Double { func nonzeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self } }
private extension Int { func nonzeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self } }

struct SettingsView: View {
    @Bindable var settings = EditorSettings.shared
    var body: some View {
        Form {
            Picker("Editor font", selection: $settings.fontName) {
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { Text($0).tag($0) }
            }
            Stepper("Font size: \(Int(settings.fontSize))", value: $settings.fontSize, in: 9...36)
            Stepper("Tab width: \(settings.tabWidth)", value: $settings.tabWidth, in: 1...16)
            Toggle("Indent using spaces", isOn: $settings.spaces)
            Toggle("Wrap new workspaces by default", isOn: $settings.wrap)
            Picker("Theme", selection: $settings.theme) {
                ForEach(["System", "Light", "Dark", "Solarized", "Midnight"], id: \.self) { Text($0).tag($0) }
            }
            TextField("LSP server command", text: $settings.lspCommand)
            Text("Executable and arguments for the workspace language server (for example: sourcekit-lsp). Restart the server from the command palette after changing this.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 480)
    }
}
