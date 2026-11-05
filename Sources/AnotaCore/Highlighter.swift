import Foundation
import SwiftTreeSitter
import TreeSitterGrammars

public enum Token: Sendable, CaseIterable {
    case keyword, string, comment, number, type, key, heading, link, emphasis, function
}

/// Turns text into colored token ranges. Uses tree-sitter when the language has a bundled grammar
/// (see `TreeSitterEngine`), otherwise the regex lexer below.
public final class Highlighter: @unchecked Sendable {  // used from one actor at a time
    private enum Engine {
        case treeSitter(TreeSitterEngine)
        case regex(NSRegularExpression, [Token])
        case none
    }

    private let engine: Engine

    public init(_ language: Language) {
        if let ts = TreeSitterEngine(language) {
            engine = .treeSitter(ts)
            return
        }
        let rules = language.rules
        if !rules.isEmpty, let re = try? NSRegularExpression(
            pattern: rules.map { "(\($0.0))" }.joined(separator: "|"), options: [.anchorsMatchLines]) {
            engine = .regex(re, rules.map(\.1))
        } else {
            engine = .none
        }
    }

    public var usesTreeSitter: Bool {
        if case .treeSitter = engine { return true }
        return false
    }

    /// Number of regex capture groups (regex engine only); equals rule count when rules are well-formed.
    public var groupCount: Int {
        if case .regex(let re, _) = engine { return re.numberOfCaptureGroups }
        return 0
    }

    /// Tokens ordered so that applying them in sequence lets inner ranges override outer ones.
    public func tokens(in text: String, range: NSRange? = nil) -> [(range: NSRange, token: Token)] {
        let r = range ?? NSRange(location: 0, length: (text as NSString).length)
        switch engine {
        case .treeSitter(let ts): return ts.tokens(in: text, range: r)
        case .regex(let re, let tokens): return Self.regexTokens(re, tokens, text, r)
        case .none: return []
        }
    }

    /// Regex lexer: every rule is one alternative of a single regex, scanned left to right.
    /// The leftmost match wins (so `"// x"` is a string, `// "x"` is a comment); at the same
    /// position the earlier rule wins. Rule patterns must not contain capturing groups.
    /// ponytail: regex lexing, no real grammar; languages move to tree-sitter by adding a grammar.
    private static func regexTokens(_ re: NSRegularExpression, _ tokens: [Token], _ text: String,
                                    _ r: NSRange) -> [(range: NSRange, token: Token)] {
        var out: [(NSRange, Token)] = []
        re.enumerateMatches(in: text, range: r) { m, _, _ in
            guard let m else { return }
            for i in 1..<m.numberOfRanges where m.range(at: i).location != NSNotFound {
                out.append((m.range, tokens[i - 1]))
                return
            }
        }
        return out
    }
}

/// Full parse + highlights query per call.
/// ponytail: re-parses the whole document each time (fast for config-sized files);
/// switch to incremental `tree.edit` + reparse if large files lag.
private final class TreeSitterEngine {
    private let parser = Parser()
    private let query: Query

    init?(_ language: Language) {
        let grammar: OpaquePointer
        switch language {
        case .json: grammar = tree_sitter_json()
        case .yaml: grammar = tree_sitter_yaml()
        case .toml: grammar = tree_sitter_toml()
        case .ini: grammar = tree_sitter_ini()
        case .python: grammar = tree_sitter_python()
        case .javascript: grammar = tree_sitter_javascript()
        case .typescript: grammar = tree_sitter_typescript()
        case .tsx: grammar = tree_sitter_tsx()
        case .go: grammar = tree_sitter_go()
        case .c: grammar = tree_sitter_c()
        case .cpp: grammar = tree_sitter_cpp()
        case .rust: grammar = tree_sitter_rust()
        case .swift: grammar = tree_sitter_swift()
        default: return nil  // regex lexer (Markdown, HTML, CSS, shell, Java, Ruby, SQL…)
        }
        let lang = SwiftTreeSitter.Language(grammar)
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "scm", subdirectory: "Queries"),
              let query = try? Query(language: lang, url: url),
              (try? parser.setLanguage(lang)) != nil
        else { return nil }
        self.query = query
    }

    func tokens(in text: String, range: NSRange) -> [(range: NSRange, token: Token)] {
        guard let tree = parser.parse(text) else { return [] }
        let cursor = query.execute(in: tree)
        cursor.setRange(range)
        // One token per range. Upstream queries disagree on precedence (tree-sitter-json lists specific
        // patterns first, toml/yaml list them last), so: more specific capture name wins
        // (string.special.key > string), ties go to the later pattern.
        var best: [NSRange: (rank: (Int, Int), token: Token)] = [:]
        for match in cursor.resolve(with: .init(string: text)) {
            for c in match.captures {
                guard let name = c.name, let t = Token(capture: name) else { continue }
                let rank = (c.nameComponents.count, c.patternIndex)
                if let old = best[c.range], old.rank >= rank { continue }
                best[c.range] = (rank, t)
            }
        }
        let found = best.map { (range: $0.key, token: $0.value.token) }
        // Outer before inner, so nested captures (escapes inside strings) are applied last.
        return found.sorted { ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length) }
    }
}

extension Token {
    /// Map tree-sitter capture names (nvim/helix conventions) onto our token kinds.
    init?(capture name: String) {
        let root = name.split(separator: ".").first.map(String.init) ?? name
        switch name {
        case "string.special.key", "property", "variable.member": self = .key
        case "string.special": self = .number  // TOML dates/times
        case "escape", "string.escape", "variable.builtin": self = .keyword
        case "constant.builtin": self = .keyword
        case "tag": self = .keyword  // JSX/TSX elements
        default:
            switch root {
            case "comment": self = .comment
            case "string": self = .string
            case "number", "float": self = .number
            case "boolean", "keyword", "include", "conditional", "repeat": self = .keyword
            case "constant": self = .number  // enum cases, ALL_CAPS constants
            case "type", "label", "attribute", "constructor", "module", "namespace": self = .type
            case "function", "method": self = .function
            case "character": self = .string
            case "markup": self = name.hasPrefix("markup.heading") ? .heading : .emphasis
            default: return nil  // punctuation, operators, @none, @spell…
            }
        }
    }
}

extension Language {
    var rules: [(String, Token)] {
        let dq = #""(?:\\.|[^"\\\n])*""#
        let sq = #"'(?:\\.|[^'\\\n])*'"#
        let bt = #"`(?:\\.|[^`\\])*`"#
        let num = #"\b(?:0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
        let slash = #"//[^\n]*"#
        let block = #"/\*[\s\S]*?\*/"#
        let hash = #"#[^\n]*"#
        let cap = #"\b[A-Z][A-Za-z0-9_]*\b"#
        func kw(_ words: String, caseInsensitive: Bool = false) -> String {
            (caseInsensitive ? "(?i:" : "(?:") + #"\b(?:"# + words.split(separator: " ").joined(separator: "|") + #")\b)"#
        }
        let cFamily = [(block, Token.comment), (slash, .comment), (dq, .string), (sq, .string)]

        switch self {
        case .plain:
            return []
        case .swift:
            return [(block, .comment), (slash, .comment), (#""""[\s\S]*?""""#, .string), (dq, .string),
                    (kw("actor any as associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in init inout internal is lazy let mutating nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while"), .keyword),
                    (#"@\w+"#, .keyword), (cap, .type), (num, .number)]
        case .python:
            return [(hash, .comment), (#""""[\s\S]*?"""|'''[\s\S]*?'''"#, .string), (dq, .string), (sq, .string),
                    (kw("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return self True try while with yield match case"), .keyword),
                    (#"@\w+"#, .keyword), (cap, .type), (num, .number)]
        case .javascript, .typescript, .tsx:
            return [(block, .comment), (slash, .comment), (bt, .string), (dq, .string), (sq, .string),
                    (kw("abstract any as async await boolean break case catch class const constructor continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface keyof let module namespace new null number of private protected public readonly return set static string super switch this throw true try type typeof undefined var void while with yield"), .keyword),
                    (cap, .type), (num, .number)]
        case .json:
            return [(block, .comment), (slash, .comment), (#""(?:\\.|[^"\\\n])*"(?=\s*:)"#, .key), (dq, .string),
                    (kw("true false null"), .keyword), (#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number)]
        case .yaml:
            return [(#"(?:^|(?<=\s))#[^\n]*"#, .comment), (#"^(?:---|\.\.\.)\s*$"#, .heading),
                    (#"^[ \t]*(?:- +)?[^\s#:'"\-][^:\n#]*?(?=:(?:\s|$))"#, .key), (dq, .string), (sq, .string),
                    (kw("true false null yes no on off"), .keyword), (#"[&*][\w-]+"#, .type), (#"![\w!]+"#, .type), (num, .number)]
        case .toml:
            return [(hash, .comment), (#"^[ \t]*\[\[?[^\]\n]*\]\]?"#, .heading), (#"^[ \t]*[\w.\-"']+(?=\s*=)"#, .key),
                    (#""""[\s\S]*?"""|'''[\s\S]*?'''"#, .string), (dq, .string), (sq, .string),
                    (kw("true false"), .keyword), (num, .number)]
        case .ini:
            return [(#"^[ \t]*[;#][^\n]*"#, .comment), (#"^[ \t]*\[[^\]\n]*\]"#, .heading),
                    (#"^[ \t]*(?:export[ \t]+)?[^=:\n\[;#]+?(?=[ \t]*[=:])"#, .key), (dq, .string), (sq, .string),
                    (kw("true false yes no on off"), .keyword), (num, .number)]
        case .markdown:
            return [(#"^```[\s\S]*?^```"#, .string), (#"^#{1,6}[ \t][^\n]*"#, .heading), (#"`[^`\n]+`"#, .string),
                    (#"!?\[[^\]\n]*\]\([^)\n]*\)"#, .link), (#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, .emphasis),
                    (#"^[ \t]*>[^\n]*"#, .comment), (#"^[ \t]*(?:[-*+]|\d+\.)(?=[ \t])"#, .keyword)]
        case .html, .xml:
            return [(#"<!--[\s\S]*?-->"#, .comment), (#"<!\[CDATA\[[\s\S]*?\]\]>"#, .string), (#"</?[\w:.-]+|/?>"#, .keyword),
                    (#"\b[\w:.-]+(?==)"#, .key), (dq, .string), (sq, .string)]
        case .css:
            return [(block, .comment), (dq, .string), (sq, .string), (#"@[\w-]+"#, .keyword),
                    (#"[\w-]+(?=\s*:[^;{}\n]*[;}])"#, .key), (#"#[0-9a-fA-F]{3,8}\b"#, .number),
                    (#"-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg)?\b"#, .number)]
        case .shell:
            return [(#"(?:^|(?<=\s))#[^\n]*"#, .comment), (dq, .string), (sq, .string),
                    (kw("if then else elif fi for while until do done case esac function return export local in select readonly source alias unset shift exit"), .keyword),
                    (#"\$\{[^}\n]*\}|\$\w+"#, .type), (num, .number)]
        case .c, .cpp:
            return [(#"^[ \t]*#[ \t]*\w+"#, .keyword)] + cFamily +
                [(kw("auto bool break case catch char class const constexpr continue default delete do double else enum explicit extern false float for friend goto if inline int long namespace new nullptr operator private protected public register return short signed sizeof static struct switch template this throw true try typedef typename union unsigned using virtual void volatile while @interface @implementation @end @property"), .keyword),
                 (cap, .type), (num, .number)]
        case .rust:
            return cFamily.filter { $0.0 != sq } +
                [(kw("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"), .keyword),
                 (#"\b\w+!"#, .keyword), (cap, .type), (num, .number)]
        case .go:
            return [(block, .comment), (slash, .comment), (bt, .string), (dq, .string), (sq, .string),
                    (kw("break case chan const continue default defer else fallthrough false for func go goto if import interface iota map nil package range return select struct switch true type var"), .keyword),
                    (cap, .type), (num, .number)]
        case .java:
            return cFamily +
                [(kw("abstract boolean break byte case catch char class const continue data default do double else enum extends final finally float for fun if implements import instanceof int interface long native new null object override package private protected public return short static super switch synchronized this throw throws true false try val var void volatile when while"), .keyword),
                 (#"@\w+"#, .keyword), (cap, .type), (num, .number)]
        case .ruby:
            return [(hash, .comment), (dq, .string), (sq, .string),
                    (kw("alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader"), .keyword),
                    (#":\w+"#, .type), (cap, .type), (num, .number)]
        case .sql:
            return [(#"--[^\n]*"#, .comment), (block, .comment), (sq, .string), (dq, .key),
                    (kw("select from where and or not insert into values update set delete create table drop alter add index primary key foreign references join left right inner outer on group by order having limit offset as distinct null is in like between case when then else end union all exists default unique view", caseInsensitive: true), .keyword),
                    (num, .number)]
        }
    }
}
