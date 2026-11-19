// Created by yuxilong on 2026/10/22.

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// 仅生成存储属性，日志求值和来源信息仍由调用处的 LogChannel 方法处理。
struct LogMemberMacro: MemberMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        let isEnum = declaration.is(EnumDeclSyntax.self)
        // 协议和扩展不能承载这里要求的私有存储属性。
        guard isEnum || declaration.is(ClassDeclSyntax.self)
            || declaration.is(StructDeclSyntax.self) || declaration.is(ActorDeclSyntax.self)
        else {
            throw MacroExpansionErrorMessage("@Logger only supports class, struct, actor, or enum declarations")
        }

        // 固定模块名避免插值依赖实例状态，也避免为每个实例重复执行表达式。
        guard case let .argumentList(arguments) = node.arguments,
              arguments.count == 1,
              let literal = arguments.first?.expression.as(StringLiteralExprSyntax.self),
              literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) })
        else {
            throw MacroExpansionErrorMessage("@Logger requires a string literal without interpolation")
        }

        // 不接管已有入口；明确报错，让调用方删除旧属性或移除宏。
        guard !declaresJournal(in: declaration.memberBlock.members) else {
            throw MacroExpansionErrorMessage(
                "@Logger cannot generate log because this type already declares a member named log",
            )
        }

        let excludesStaticStorage = ([Syntax(declaration)] + context.lexicalContext).contains { syntax in
            syntax.as(ClassDeclSyntax.self)?.genericParameterClause != nil
                || syntax.as(StructDeclSyntax.self)?.genericParameterClause != nil
                || syntax.as(ActorDeclSyntax.self)?.genericParameterClause != nil
                || syntax.as(EnumDeclSyntax.self)?.genericParameterClause != nil
                // shortcut: 宏无法解析 extension 所指类型的泛型信息；需要静态入口时把声明移回类型体。
                || syntax.is(ExtensionDeclSyntax.self)
        }
        var members: [DeclSyntax] = []
        // Swift 不支持泛型类型的静态存储属性，包括泛型类型中的非泛型嵌套类型。
        if !excludesStaticStorage {
            members.append("private static let log = LogChannel(\(literal))")
        }
        // enum 只能包含计算型实例属性，本宏按约定不提供计算属性替代。
        if !isEnum {
            members.append("private let log = LogChannel(\(literal))")
        }
        return members
    }

    private static func declaresJournal(in members: MemberBlockItemListSyntax) -> Bool {
        for member in members {
            // 条件编译中的声明也可能与生成属性冲突，提前给出可定位的诊断。
            if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
                for clause in conditional.clauses {
                    if case let .decls(declarations) = clause.elements, declaresJournal(in: declarations) {
                        return true
                    }
                }
            }
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if binding.pattern.tokens(viewMode: .sourceAccurate).contains(where: { $0.text == "log" }) {
                        return true
                    }
                }
            }
            // enum case 也占用静态成员名，不能与生成的静态 log 共存。
            if let cases = member.decl.as(EnumCaseDeclSyntax.self),
               cases.elements.contains(where: { $0.name.text == "log" }) {
                return true
            }
            if let named = member.decl.asProtocol(NamedDeclSyntax.self), named.name.text == "log" {
                return true
            }
        }
        return false
    }
}

/// 编译宿主插件入口，不进入 iOS 运行时。
@main
struct LogKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [LogMemberMacro.self]
}
