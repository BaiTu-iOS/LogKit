// Created by yuxilong on 2026/10/22.

import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import LogCompilerPlugin

/// 验证生成矩阵、嵌套泛型边界和可定位的错误信息。
struct LogMacroTests {
    @Test(arguments: ["class", "final class", "struct", "actor"])
    func `concrete types`(kind: String) {
        check(
            "@Logger(\"Catalog\")\n\(kind) Service {}",
            expanded: """
            \(kind) Service {

                private static let log = LogChannel("Catalog")

                private let log = LogChannel("Catalog")
            }
            """,
        )
    }

    @Test
    func `enum only generates static storage`() {
        check(
            "@Logger(\"Catalog\")\nenum LanguageFetch {}",
            expanded: """
            enum LanguageFetch {

                private static let log = LogChannel("Catalog")
            }
            """,
        )
    }

    @Test(arguments: ["class", "struct", "actor"])
    func `generic types only generate instance storage`(kind: String) {
        check(
            "@Logger(\"Catalog\")\n\(kind) Service<T> {}",
            expanded: """
            \(kind) Service<T> {

                private let log = LogChannel("Catalog")
            }
            """,
        )
    }

    @Test
    func `generic enum generates nothing`() {
        check("@Logger(\"Catalog\")\nenum Service<T> {}", expanded: "enum Service<T> {}")
    }

    @Test
    func `nested generic context skips static storage`() {
        check(
            """
            struct Outer<T> {
                @Logger("Catalog")
                struct Inner {
                }
            }
            """,
            expanded: """
            struct Outer<T> {
                struct Inner {

                    private let log = LogChannel("Catalog")
                }
            }
            """,
        )
    }

    @Test(arguments: ["protocol Service {}", "extension Service {}"])
    func `rejects unsupported declarations`(declaration: String) {
        check(
            "@Logger(\"Catalog\")\n\(declaration)", expanded: declaration,
            error: "@Logger only supports class, struct, actor, or enum declarations",
        )
    }

    @Test(arguments: ["moduleName", #""Module\(value)""#])
    func `rejects dynamic module names`(argument: String) {
        check(
            "@Logger(\(argument))\nstruct Service {}", expanded: "struct Service {}",
            error: "@Logger requires a string literal without interpolation",
        )
    }

    @Test(arguments: [
        "let log = 1",
        "static let log = 1",
        "func log() {}",
        "typealias log = Int",
        "let (log, other) = (1, 2)"
    ])
    func `rejects existing members`(member: String) {
        let declaration = """
        struct Service {
            \(member)
        }
        """
        check(
            "@Logger(\"Catalog\")\n\(declaration)", expanded: declaration,
            error: "@Logger cannot generate log because this type already declares a member named log",
        )
    }

    @Test
    func `rejects conditionally declared log`() {
        let declaration = """
        struct Service {
            #if DEBUG
            let log = 1
            #endif
        }
        """
        check(
            "@Logger(\"Catalog\")\n\(declaration)", expanded: declaration,
            error: "@Logger cannot generate log because this type already declares a member named log",
        )
    }

    @Test
    func `preserves raw string literal`() {
        check(
            ##"@Logger(#"Locale\Table"#)"## + "\nstruct Service {}",
            expanded: ##"""
            struct Service {

                private static let log = LogChannel(#"Locale\Table"#)

                private let log = LogChannel(#"Locale\Table"#)
            }
            """##,
        )
    }

    @Test
    func `rejects enum case log`() {
        let declaration = """
        enum Service {
            case log
        }
        """
        check(
            "@Logger(\"Catalog\")\n\(declaration)", expanded: declaration,
            error: "@Logger cannot generate log because this type already declares a member named log",
        )
    }

    private func check(_ source: String, expanded: String, error: String? = nil) {
        assertMacroExpansion(
            source,
            expandedSource: expanded,
            diagnostics: error.map { [DiagnosticSpec(message: $0, line: 1, column: 1)] } ?? [],
            macroSpecs: ["Logger": MacroSpec(type: LogMemberMacro.self)],
            indentationWidth: .spaces(4),
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) },
        )
    }
}
