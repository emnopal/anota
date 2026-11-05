import Foundation

public enum Language: String, CaseIterable, Codable, Sendable, Identifiable {
    case plain, swift, python, javascript, typescript, tsx, json, yaml, toml, ini, markdown
    case html, xml, css, shell, c, cpp, rust, go, java, ruby, sql
    case dotenv, log, batch, powershell

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plain: "Plain Text"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .tsx: "TSX"
        case .json: "JSON"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .ini: "Config (INI)"
        case .dotenv: "Environment (.env)"
        case .shell: "Shell (Bash/Zsh)"
        case .batch: "Batch"
        case .powershell: "PowerShell"
        case .html: "HTML"
        case .xml: "XML"
        case .css: "CSS"
        case .cpp: "C++"
        case .sql: "SQL"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    public static func detect(_ url: URL?) -> Language {
        guard let url else { return .plain }
        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix(".env") || name.hasSuffix(".env") { return .dotenv }
        if [".editorconfig", ".gitconfig", ".npmrc", ".gitmodules"].contains(name) { return .ini }
        if name == "makefile" || [".zshrc", ".zshenv", ".zprofile", ".zlogin", ".zlogout", ".bashrc", ".bash_profile",
                                  ".bash_aliases", ".bash_logout", ".profile"].contains(name) { return .shell }
        if name.contains(".log.") { return .log }  // rotated logs: app.log.1
        if name == "dockerfile" { return .shell }
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "py", "pyw": return .python
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "mts", "cts": return .typescript
        case "tsx": return .tsx
        case "json", "jsonc", "json5", "geojson": return .json
        case "yml", "yaml": return .yaml
        case "toml": return .toml
        case "ini", "cfg", "conf", "properties": return .ini
        case "env": return .dotenv
        case "log": return .log
        case "bat", "cmd": return .batch
        case "ps1", "psm1", "psd1": return .powershell
        case "md", "markdown", "mdown": return .markdown
        case "html", "htm", "vue", "svelte": return .html
        case "xml", "plist", "svg", "xib", "storyboard": return .xml
        case "css", "scss", "less": return .css
        case "sh", "bash", "zsh", "fish", "command": return .shell
        case "c", "h", "m": return .c
        case "cc", "cpp", "cxx", "hpp", "hh", "mm": return .cpp
        case "rs": return .rust
        case "go": return .go
        case "java", "kt", "kts", "scala": return .java
        case "rb", "rake", "gemspec": return .ruby
        case "sql": return .sql
        default: return .plain
        }
    }
}
