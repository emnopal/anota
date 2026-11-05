import Foundation
import SwiftTreeSitter
import TreeSitterGrammars

public enum Token: Sendable, CaseIterable {
    case keyword, string, comment, number, type, key, heading, link, emphasis, function
    case error, warning, info  // log levels
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

    /// One-shot: tokens for `text` from scratch (no incremental state). Used by tests and small callers.
    public func tokens(in text: String, range: NSRange? = nil) -> [(range: NSRange, token: Token)] {
        let ns = text as NSString
        if case .treeSitter(let ts) = engine { ts.reset() }
        _ = update(ns)
        return tokens(in: ns, range: range ?? NSRange(location: 0, length: ns.length))
    }

    /// Forget the parse; the next `update` parses from scratch.
    public func reset() {
        if case .treeSitter(let ts) = engine { ts.reset() }
    }

    /// Record an edit (from NSTextStorage: `range` is the edited range in the new text, `delta` the
    /// change in length) so the next `update` re-parses incrementally.
    public func edited(_ range: NSRange, changeInLength delta: Int, lines: LineIndex) {
        if case .treeSitter(let ts) = engine { ts.edited(range, delta: delta, lines: lines) }
    }

    /// Bring the parse up to date with `text`. Returns ranges whose highlighting may have changed
    /// beyond the edited lines (e.g. an opened string or comment), tree-sitter only.
    public func update(_ text: NSString) -> [NSRange] {
        if case .treeSitter(let ts) = engine { return ts.update(text) }
        return []
    }

    /// Tokens in `range` of the current parse (call `update` first), ordered so that applying them
    /// in sequence lets inner ranges override outer ones.
    public func tokens(in text: NSString, range: NSRange) -> [(range: NSRange, token: Token)] {
        switch engine {
        case .treeSitter(let ts): return ts.tokens(in: text, range: range)
        case .regex(let re, let tokens): return Self.regexTokens(re, tokens, text as String, range)
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

/// Incremental tree-sitter: edits are applied to the previous tree and only changed parts re-parse.
private final class TreeSitterEngine {
    private let parser = Parser()
    private let query: Query
    private var tree: MutableTree?
    private var dirty = true

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
        case .shell: grammar = tree_sitter_bash()
        default: return nil  // regex lexer (Markdown, HTML, CSS, shell, Java, Ruby, SQL…)
        }
        let lang = SwiftTreeSitter.Language(grammar)
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "scm", subdirectory: "Queries"),
              let query = try? Query(language: lang, url: url),
              (try? parser.setLanguage(lang)) != nil
        else { return nil }
        self.query = query
    }

    func reset() { tree = nil; dirty = true }

    func edited(_ range: NSRange, delta: Int, lines: LineIndex) {
        dirty = true
        guard let tree else { return }
        let start = range.location, newEnd = NSMaxRange(range), oldEnd = newEnd - delta
        // UTF-16LE: byte = 2 × UTF-16 offset. The old end point is approximate (the old text is gone);
        // highlighting works on byte offsets, which are exact.
        let startPoint = point(start, lines)
        let newEndPoint = point(newEnd, lines)
        let oldEndPoint = Point(row: startPoint.row, column: startPoint.column + UInt32(max(oldEnd - start, 0) * 2))
        tree.edit(InputEdit(startByte: start * 2, oldEndByte: max(oldEnd, start) * 2, newEndByte: newEnd * 2,
                            startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: newEndPoint))
    }

    private func point(_ offset: Int, _ lines: LineIndex) -> Point {
        let line = lines.line(at: offset)
        return Point(row: UInt32(line - 1), column: UInt32((offset - lines.start(ofLine: line)) * 2))
    }

    func update(_ text: NSString) -> [NSRange] {
        guard dirty else { return [] }
        dirty = false
        let old = tree
        let length = text.length
        // Read straight from the NSString's UTF-16 buffer in chunks: O(1) per chunk.
        let new = parser.parse(tree: old, readBlock: { byte, _ in
            let loc = byte / 2
            guard loc < length else { return nil }
            let n = min(16_384, length - loc)
            var data = Data(count: n * 2)
            data.withUnsafeMutableBytes { raw in
                text.getCharacters(raw.baseAddress!.assumingMemoryBound(to: unichar.self), range: NSRange(location: loc, length: n))
            }
            return data
        })
        tree = new
        guard let old, let new else { return [] }
        return old.changedRanges(from: new).map {
            NSRange(location: Int($0.bytes.lowerBound) / 2, length: Int($0.bytes.upperBound - $0.bytes.lowerBound) / 2)
        }
    }

    func tokens(in text: NSString, range: NSRange) -> [(range: NSRange, token: Token)] {
        if dirty { _ = update(text) }
        guard let tree else { return [] }
        let cursor = query.execute(in: tree)
        cursor.setRange(range)
        let context = Predicate.Context(textProvider: { r, _ in
            NSMaxRange(r) <= text.length ? text.substring(with: r) : nil
        })
        // One token per range. Upstream queries disagree on precedence (tree-sitter-json lists specific
        // patterns first, toml/yaml list them last), so: more specific capture name wins
        // (string.special.key > string), ties go to the later pattern.
        var best: [NSRange: (rank: (Int, Int), token: Token)] = [:]
        for match in cursor.resolve(with: context) {
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
        case .dotenv:
            return [(#"(?:^|(?<=\s))#[^\n]*"#, .comment), (kw("export"), .keyword),
                    (#"[A-Za-z_][A-Za-z0-9_.]*(?=[ \t]*=)"#, .key), (dq, .string), (sq, .string),
                    (#"\$\{[^}\n]*\}|\$\w+"#, .type), (kw("true false yes no on off null", caseInsensitive: true), .keyword), (num, .number)]
        case .log:
            return [(#"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?|\b\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\b"#, .type),
                    (kw("FATAL CRITICAL CRIT ERROR ERR SEVERE PANIC EMERG ALERT FAIL FAILED", caseInsensitive: true), .error),
                    (#"\b[A-Za-z_.]+(?:Exception|Error)\b"#, .error),
                    (kw("WARN WARNING", caseInsensitive: true), .warning),
                    (kw("INFO NOTICE OK SUCCESS", caseInsensitive: true), .info),
                    (kw("DEBUG TRACE VERBOSE FINE FINER FINEST", caseInsensitive: true), .comment),
                    (#"^[ \t]+at [^\n]*"#, .comment),  // stack frames
                    (#"\b[a-z][a-z0-9+.-]*://[^\s"'<>]+"#, .link), (dq, .string),
                    (#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, .number),
                    (#"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#, .number), (num, .number)]
        case .batch:
            return [(#"(?i:^[ \t]*@?rem\b[^\n]*)|^[ \t]*::[^\n]*"#, .comment), (#"^:\w+"#, .function), (dq, .string),
                    (#"%~?[\w:]+%|%%~?\w|![\w:]+!|%[0-9*]"#, .type),
                    (kw("echo set setlocal endlocal if else goto call exit for in do not exist defined errorlevel equ neq lss leq gtr geq shift start cd pushd popd off on nul cls pause choice title", caseInsensitive: true), .keyword),
                    (num, .number)]
        case .powershell:
            return [(#"<#[\s\S]*?#>"#, .comment), (#"#[^\n]*"#, .comment),
                    (#"@"[\s\S]*?\n"@|@'[\s\S]*?\n'@"#, .string), (dq, .string), (sq, .string),
                    (#"\$(?:\{[^}\n]*\}|[\w:?]+)"#, .type), (#"\[[\w.]+(?:\[\])?\]"#, .type),
                    (kw("function param begin process end if elseif else switch foreach for while do until return break continue try catch finally throw trap filter class enum using in exit", caseInsensitive: true), .keyword),
                    (#"(?i:-(?:eq|ne|gt|ge|lt|le|like|notlike|match|notmatch|contains|notcontains|in|notin|and|or|not|xor|replace|split|join|is|isnot|as|f)\b)"#, .keyword),
                    (#"\b[A-Z][a-z]+-[A-Z][A-Za-z]+\b"#, .function), (num, .number)]
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
