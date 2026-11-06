// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Anota",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.4.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        // Tree-sitter core. Grammars are vendored (scripts/vendor-grammars.sh), not packages.
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.25.0"),
    ],
    targets: [
        // Pure logic (no AppKit): file decoding, highlighting rules, session store, parsers.
        .target(
            name: "AnotaCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"), "Yams", "TOMLKit",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                "TreeSitterGrammars",
            ],
            resources: [.copy("Queries")]  // highlights.scm per grammar
        ),
        // Generated C for every tree-sitter grammar we highlight (see Vendor/TreeSitterGrammars/README.md).
        .target(
            name: "TreeSitterGrammars",
            path: "Vendor/TreeSitterGrammars",
            sources: [
                "json/src/parser.c",
                "yaml/src/parser.c", "yaml/src/scanner.c",  // scanner #includes yaml/src/schema.*.c
                "toml/src/parser.c", "toml/src/scanner.c",
                "ini/src/parser.c",
                "python/src/parser.c", "python/src/scanner.c",
                "javascript/src/parser.c", "javascript/src/scanner.c",
                "typescript/typescript/src/parser.c", "typescript/typescript/src/scanner.c",
                "typescript/tsx/src/parser.c", "typescript/tsx/src/scanner.c",
                "go/src/parser.c",
                "c/src/parser.c",
                "cpp/src/parser.c", "cpp/src/scanner.c",
                "rust/src/parser.c", "rust/src/scanner.c",
                "swift/src/parser.c", "swift/src/scanner.c",
                "bash/src/parser.c", "bash/src/scanner.c",
            ],
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-w", "-O2"])]  // generated C: no warnings; parse tables are slow at -O0
        ),
        .executableTarget(
            name: "Anota",
            dependencies: ["AnotaCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AnotaTests", dependencies: ["Anota", "AnotaCore"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "AnotaCoreTests", dependencies: ["AnotaCore"], resources: [.copy("Fixtures")]),
    ]
)
