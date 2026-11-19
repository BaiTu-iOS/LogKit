// Created by yuxilong on 2026/10/22.

import LogKit
import Testing

/// 日志后端是进程级状态，串行验证惰性求值和旧接口兼容性。
@MainActor
@Suite(.serialized)
struct LogChannelTests {

    @Test
    func `filtered messages are not evaluated`() {
        let log = LogChannel("Lazy")
        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return "expensive"
        }

        log.debug("value: \(message())")
        #expect(evaluations == 0)
    }

    @Test
    func `subscription evaluates message once and cancellation restores filtering`() {
        let log = LogChannel("Lazy")
        var evaluations = 0
        var events: [LKLogEntry] = []
        let subscription = LKLogCenter.shared().observe(minimumLevel: .debug) { events.append($0) }
        defer { subscription.cancel() }
        func message() -> String {
            evaluations += 1
            return "value: \(evaluations)"
        }

        log.debug(message())
        #expect(evaluations == 1)
        #expect(events.map(\.message) == ["value: 1"])
        #expect(events.map(\.category) == ["Lazy"])

        subscription.cancel()
        log.debug(message())
        #expect(evaluations == 1)
        #expect(events.count == 1)
    }

    @Test
    func `all levels preserve original message and category`() {
        let log = LogChannel("Network")
        var events: [LKLogEntry] = []
        let subscription = LKLogCenter.shared().observe(minimumLevel: .verbose) { events.append($0) }
        defer { subscription.cancel() }

        log.verbose("详细")
        log.debug("调试")
        log.info("信息 100%")
        log.warning("警告")
        log.error("错误\n详情")

        #expect(events.map(\.level) == [.verbose, .debug, .info, .warning, .error])
        #expect(events.map(\.message) == ["详细", "调试", "信息 100%", "警告", "错误\n详情"])
        #expect(events.allSatisfy { $0.category == "Network" })
    }

    @Test
    func `typed modules and existing function signatures remain usable`() {
        let module = LogCategory(rawValue: "Existing")
        let log = LogChannel(module: module)
        let legacyMethods: [(LogCategory, String) -> Void] = [
            LogOutput.debug, LogOutput.info, LogOutput.error,
        ]
        var events: [LKLogEntry] = []
        let subscription = LKLogCenter.shared().observe(minimumLevel: .debug) { events.append($0) }
        defer { subscription.cancel() }

        log.info("new")
        for method in legacyMethods {
            method(module, "legacy")
        }

        #expect(events.map(\.level) == [.info, .debug, .info, .error])
        #expect(events.map(\.message) == ["new", "legacy", "legacy", "legacy"])
        #expect(events.allSatisfy { $0.category == module.rawValue })
    }
}
