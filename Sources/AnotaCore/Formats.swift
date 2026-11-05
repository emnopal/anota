import Foundation
import Markdown
import TOMLKit
import Yams

// MARK: YAML

public enum YAML {
    /// First document only. ponytail: no source ranges (Mark has line/col only), so tree is view-only.
    public static func parse(_ text: String) throws -> Node {
        do {
            guard let root = try Yams.compose(yaml: text) else { return Node(value: .null) }
            return node(root, key: nil)
        } catch let YamlError.scanner(_, problem, mark, _), let YamlError.parser(_, problem, mark, _) {
            throw ParseError(message: problem, line: mark.line, column: mark.column)
        } catch {
            throw ParseError(message: "\(error)", line: 1, column: 1)
        }
    }

    private static func node(_ n: Yams.Node, key: String?) -> Node {
        switch n {
        case .mapping(let m):
            return Node(key: key, value: .object, children: m.map { k, v in node(v, key: k.string ?? "\(k)") })
        case .sequence(let s):
            return Node(key: key, value: .array, children: s.map { node($0, key: nil) })
        case .scalar(let s):
            if n.null != nil, s.style == .plain { return Node(key: key, value: .null) }
            if let b = n.bool, s.style == .plain { return Node(key: key, value: .bool(b)) }
            if (n.int != nil || n.float != nil), s.style == .plain { return Node(key: key, value: .number(s.string)) }
            return Node(key: key, value: .string(s.string))
        default:
            return Node(key: key, value: .string("\(n)"))
        }
    }
}

// MARK: TOML

public enum TOML {
    /// ponytail: goes through toml++'s JSON output, so keys come back sorted, not in file order.
    public static func parse(_ text: String) throws -> Node {
        do {
            return try JSON.parse(TOMLTable(string: text).convert(to: .json))
        } catch let e as TOMLParseError {
            throw ParseError(message: e.description, line: e.source.begin.line, column: e.source.begin.column)
        }
    }
}

// MARK: Markdown

public enum MarkdownHTML {
    /// Full HTML page (GitHub-like styling, light/dark) for the preview web view.
    public static func page(_ markdown: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark"><style>\(css)</style></head>
        <body><article>\(HTMLFormatter.format(markdown))</article></body></html>
        """
    }

    static let css = """
    :root { color-scheme: light dark; --fg:#1f2328; --muted:#59636e; --border:#d1d9e0; --code:#f6f8fa; --link:#0969da; }
    @media (prefers-color-scheme: dark) { :root { --fg:#e6edf3; --muted:#9198a1; --border:#3d444d; --code:#1c2128; --link:#4493f8; } }
    html { background: transparent; }
    body { font: 15px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; color: var(--fg); margin: 0; padding: 28px 36px; }
    article { max-width: 780px; margin: 0 auto; }
    h1, h2 { border-bottom: 1px solid var(--border); padding-bottom: .3em; }
    h1, h2, h3, h4 { margin: 1.4em 0 .6em; line-height: 1.25; font-weight: 600; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    code, pre { font: 13px ui-monospace, "SF Mono", Menlo, monospace; background: var(--code); border-radius: 6px; }
    code { padding: .15em .35em; } pre { padding: 14px 16px; overflow: auto; } pre code { padding: 0; background: none; }
    blockquote { margin: 0; padding: 0 1em; color: var(--muted); border-left: 3px solid var(--border); }
    table { border-collapse: collapse; } th, td { border: 1px solid var(--border); padding: 6px 12px; }
    tr:nth-child(2n) { background: var(--code); }
    img { max-width: 100%; } hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
    li > input[type=checkbox] { margin-right: .4em; }
    """
}
