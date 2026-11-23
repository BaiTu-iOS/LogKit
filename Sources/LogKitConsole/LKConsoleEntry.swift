// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Foundation
import LogCore

/// 序号在入口锁内分配，和入队顺序一致。
struct LKConsoleEntry {
    let sequence: UInt64
    let event: LKLogEntry
}

/// 列表只持有有限预览，避免 UI 快照保留被历史缓存淘汰的大正文。
struct LKConsoleRow {
    let sequence: UInt64
    let timestamp: Date
    let level: Int
    let category: String
    let preview: String
    let isMainThread: Bool

    init(_ entry: LKConsoleEntry) {
        sequence = entry.sequence
        timestamp = entry.event.timestamp
        level = entry.event.level.rawValue
        category = entry.event.category
        isMainThread = entry.event.isMainThread
        let text = entry.event.message as NSString
        preview = text.substring(to: min(text.length, 360)).trimmingCharacters(in: .newlines)
    }
}

/// 拒收与正常历史淘汰分别统计，每次展开创建新的统计会话。
struct LKConsoleStatistics {
    var accepted: UInt64 = 0
    var overloaded: UInt64 = 0
    var oversized: UInt64 = 0
    var evicted: UInt64 = 0
}

/// 发布给 UI 的轻量快照，不包含完整正文。
struct LKConsoleSnapshot {
    let rows: [LKConsoleRow]
    let categories: [String]
    let statistics: LKConsoleStatistics
    let revision: UInt64
    var historyMessage: String?
}
#endif
