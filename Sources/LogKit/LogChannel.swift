//
//  LogChannel.swift
//  LogKit
//
//  Created by yuxilong on 2021/9/26.
//

import Foundation
@_exported import LogCore

/// 绑定固定模块名的 Swift 日志入口，不可变且可跨线程共享。
///
/// 在业务类型中声明 `private static let log = LogChannel("Network")`，使用 `Self.log.info("连接成功")`。
/// 多个类型共用同一模块时也可复用模块内的文件级常量。构造只保存模块名，所有入口共用
/// `LKLogCenter.shared()`；初始化、等级配置和停止由宿主统一管理，业务模块不重复启动后端。
///
/// 五种等级的方法都在调用线程同步检查等级，并按需计算消息至多一次。不要在消息表达式中
/// 执行业务副作用，也不要提前拼接昂贵字符串。文件异步写入，订阅在调用线程同步投递；
/// 等级或订阅状态可能在求值期间变化，调用返回不保证落盘或交付。正文不自动脱敏。
/// 默认采集业务调用处的来源；已有包装方法须同时透传惰性消息与 file/function/line。
public struct LogChannel: Sendable {

    /// 固定分类，避免为每条消息创建新的控制台 category。
    public let category: String

    /// 创建轻量日志值，不启动后端，也不创建独立队列、文件或控制台对象。
    /// - Parameter module: 有限、稳定的业务名称，例如 Network；动态数据放正文。
    ///   空名称在订阅中使用 LogKit 分类。
    public init(_ module: String) {
        category = module
    }

    /// 复用旧接口中已经定义的模块常量。
    /// - Parameter module: 现有 `LogCategory` 常量；命名约定与字符串初始化相同。
    public init(module: LogCategory) {
        self.init(module.rawValue)
    }

    /// 记录详细日志，沿用历史行为：文件按 Info 写入，订阅保留 Verbose 等级。
    /// - Parameters:
    ///   - message: 按需同步求值的正文，无自动脱敏；不要包含业务副作用。
    ///   - file: 来源文件标识，默认取调用处 #fileID；包装方法应透传。
    ///   - function: 来源函数名，默认取调用处 #function；包装方法应透传。
    ///   - line: 来源行号，默认取调用处 #line；超过 INT_MAX 时按 INT_MAX 记录。
    public func verbose(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
    ) {
        log(.verbose, message, file: file, function: function, line: line)
    }

    /// 记录调试日志；初次等级检查无出口接收时不计算消息。
    /// 文件阈值为 Info 时，Debug 订阅仍可触发消息求值；无需在业务处添加 #if DEBUG。
    /// - Parameters:
    ///   - message: 按需同步求值的正文，无自动脱敏；不要包含业务副作用。
    ///   - file: 来源文件标识，默认取调用处 #fileID；包装方法应透传。
    ///   - function: 来源函数名，默认取调用处 #function；包装方法应透传。
    ///   - line: 来源行号，默认取调用处 #line；超过 INT_MAX 时按 INT_MAX 记录。
    public func debug(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
    ) {
        log(.debug, message, file: file, function: function, line: line)
    }

    /// 记录普通日志；没有出口接收时不计算消息。
    /// - Parameters:
    ///   - message: 按需同步求值的正文，无自动脱敏；不要包含业务副作用。
    ///   - file: 来源文件标识，默认取调用处 #fileID；包装方法应透传。
    ///   - function: 来源函数名，默认取调用处 #function；包装方法应透传。
    ///   - line: 来源行号，默认取调用处 #line；超过 INT_MAX 时按 INT_MAX 记录。
    public func info(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
    ) {
        log(.info, message, file: file, function: function, line: line)
    }

    /// 记录警告日志；没有出口接收时不计算消息。
    /// - Parameters:
    ///   - message: 按需同步求值的正文，无自动脱敏；不要包含业务副作用。
    ///   - file: 来源文件标识，默认取调用处 #fileID；包装方法应透传。
    ///   - function: 来源函数名，默认取调用处 #function；包装方法应透传。
    ///   - line: 来源行号，默认取调用处 #line；超过 INT_MAX 时按 INT_MAX 记录。
    public func warning(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
    ) {
        log(.warning, message, file: file, function: function, line: line)
    }

    /// 记录错误日志；没有出口接收时不计算消息。
    /// - Parameters:
    ///   - message: 按需同步求值的正文，无自动脱敏；不要包含业务副作用。
    ///   - file: 来源文件标识，默认取调用处 #fileID；包装方法应透传。
    ///   - function: 来源函数名，默认取调用处 #function；包装方法应透传。
    ///   - line: 来源行号，默认取调用处 #line；超过 INT_MAX 时按 INT_MAX 记录。
    public func error(
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
    ) {
        log(.error, message, file: file, function: function, line: line)
    }

    private func log(_ level: LKSeverity, _ message: () -> String, file: String, function: String, line: UInt) {
        let backend = LKLogCenter.shared()
        // 中控可独立接收 Debug，不能仅根据文件等级或编译配置提前丢弃。
        guard backend.shouldLog(level: level) else { return }

        backend.log(level: level, module: category, message: message(), file: file, function: function, line: line)
    }
}

/// A stable name shared by call sites in a subsystem.
@frozen
public struct LogCategory: Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Eager logging for callers that already have a formatted message.
public enum LogOutput {
        /// 输出调试日志；保留旧签名，正文在进入方法前已经求值，不采集业务调用处来源。
        /// - Parameters:
        ///   - module: 固定业务模块常量。
        ///   - message: 已计算的原文；需要惰性求值时改用 LogChannel.debug。
        public static func debug(module: LogCategory, message: String) {
            LKLogCenter.shared().logDebug(
                withModuleName: module.rawValue,
                message: message,
            )
        }

        /// 输出普通日志；保留旧签名，正文在进入方法前已经求值，不采集业务调用处来源。
        /// - Parameters:
        ///   - module: 固定业务模块常量。
        ///   - message: 已计算的原文；需要惰性求值时改用 LogChannel.info。
        public static func info(module: LogCategory, message: String) {
            LKLogCenter.shared().logInfo(
                withModuleName: module.rawValue,
                message: message,
            )
        }

        /// 输出错误日志；保留旧签名，正文在进入方法前已经求值，不采集业务调用处来源。
        /// - Parameters:
        ///   - module: 固定业务模块常量。
        ///   - message: 已计算的原文；需要惰性求值时改用 LogChannel.error。
        public static func error(module: LogCategory, message: String) {
            LKLogCenter.shared().logError(
                withModuleName: module.rawValue,
                message: message,
            )
        }
    }
