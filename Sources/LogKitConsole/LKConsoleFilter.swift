// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Foundation
import LogCore

/// 可持久化的显示条件，不改变采集或文件日志等级。
struct LKConsoleFilter: Codable, Equatable {
    var version = 1
    var categories: Set<String> = []
    var blocked: Set<String> = []
    var levels: Set<Int> = []
    var keyword = ""
    /// 本机时区选取的绝对时间边界，nil 表示不限，包含边界时刻。
    var startDate: Date?
    var endDate: Date?
    /// 保留已有偏好字段名；倒序列表中表示跟随顶部的最新日志。
    var followsTail = true

    static let defaultsKey = "LogKitConsole.filter.v1"
    static let levelNames = ["Verbose", "Debug", "Info", "Warning", "Error", "Fatal"]

    mutating func setKeyword(_ text: String) {
        let source = text as NSString
        var length = min(source.length, 512)
        // 预算与偏好校验统一使用 UTF-16，截取时保留完整代理对。
        if length > 0, (0xD800...0xDBFF).contains(source.character(at: length - 1)) { length -= 1 }
        keyword = source.substring(to: length)
    }

    func includes(_ event: LKLogEntry) -> Bool {
        // 屏蔽优先于包含；空选择表示全部。
        guard !blocked.contains(event.category),
              categories.isEmpty || categories.contains(event.category) else { return false }
        guard levels.isEmpty || levels.contains(event.level.rawValue) else { return false }
        if let startDate, event.timestamp < startDate { return false }
        if let endDate, event.timestamp > endDate { return false }
        return keyword.isEmpty || event.message.range(of: keyword, options: [.caseInsensitive, .literal]) != nil
    }

    static func load(from defaults: UserDefaults = .standard) -> LKConsoleFilter {
        // 损坏或不支持的版本回退默认，不将异常偏好带入日志热路径。
        guard let data = defaults.data(forKey: defaultsKey), data.count <= 256 * 1024,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1,
              value.categories.count <= 256, value.blocked.count <= 256, value.keyword.utf16.count <= 512,
              value.categories.union(value.blocked).allSatisfy({ $0.utf16.count <= 256 }),
              value.levels.allSatisfy({ levelNames.indices.contains($0) }),
              value.startDate?.timeIntervalSince1970.isFinite != false,
              value.endDate?.timeIntervalSince1970.isFinite != false,
              (value.startDate ?? .distantPast) <= (value.endDate ?? .distantFuture) else { return Self() }
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        // 只有编码成功才覆盖上次有效偏好。
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
#endif
