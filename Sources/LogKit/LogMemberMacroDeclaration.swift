// Created by yuxilong on 2026/10/22.

/// 为类型生成私有的实例和静态 `let log = LogChannel(module)`；Swift 调用方引入 LogKit。
/// - Parameter module: 固定模块名，只接受不含插值的字符串字面量。
/// enum 跳过实例属性；泛型及其嵌套类型、extension 内嵌套类型跳过静态属性。
/// 已有 log 成员时报告编译错误。
/// 实例存储属性会参与 Codable/Equatable/Hashable 等协议的自动合成，请自行排除或实现协议。
@attached(member, names: named(log))
public macro Logger(_ module: String) = #externalMacro(module: "LogCompilerPlugin", type: "LogMemberMacro")
