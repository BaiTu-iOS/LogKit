// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Foundation
import LogCore

/// 有界入口与串行历史。查询和写入使用同一串行队列，新增日志不会使查询失效。
final class LKConsoleStore {
    let queue = DispatchQueue(label: "com.baitu.logger.console.store", qos: .utility)
    let lock = NSLock()
    let historyLimit: Int
    let historyByteLimit: Int
    let inletLimit: Int
    let inletByteLimit: Int
    var active = true
    var pending: [LKConsoleEntry] = []
    var pendingBytes = 0
    var scheduled = false
    var sequence: UInt64 = 0
    var statistics = LKConsoleStatistics()
    var requestedFilter: LKConsoleFilter
    var requestedRevision: UInt64 = 0
    var observer: ((LKConsoleSnapshot) -> Void)?
    var pendingSnapshot: LKConsoleSnapshot?
    var delivering = false
    var immediatePublication = false

    // 以下状态只由 queue 访问；固定槽位避免每条删除数组头部。
    var ring: [LKConsoleEntry?]
    var head = 0
    var count = 0
    var historyBytes = 0
    var categoryDirectory: Set<String> = []
    var filter: LKConsoleFilter
    var revision: UInt64 = 0
    var rows: [LKConsoleRow] = []
    var historyMessage: String?
    private var lastPublication: TimeInterval = 0
    private var publicationScheduled = false
    static let refreshInterval: TimeInterval = 5

    init(filter: LKConsoleFilter, historyLimit: Int = 5000, historyByteLimit: Int = 10 * 1024 * 1024,
         inletLimit: Int = 1000, inletByteLimit: Int = 1024 * 1024) {
        self.filter = filter
        requestedFilter = filter
        self.historyLimit = max(1, historyLimit)
        self.historyByteLimit = max(1, historyByteLimit)
        self.inletLimit = max(1, inletLimit)
        self.inletByteLimit = max(1, inletByteLimit)
        ring = Array(repeating: nil, count: max(1, historyLimit))
    }

    func receive(_ event: LKLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        // 旧订阅的在途回调不得恢复关闭的会话。
        guard active else { return }
        let bytes = Int(event.payloadByteCount)
        // 正文和 category 均有硬上限；预算以 UTF-16 有效载荷计量。
        guard bytes <= min(inletByteLimit, historyByteLimit), event.category.utf16.count <= 256 else {
            statistics.oversized += 1
            scheduleLocked()
            return
        }
        guard pending.count < inletLimit, bytes <= inletByteLimit - pendingBytes else {
            statistics.overloaded += 1
            scheduleLocked()
            return
        }
        sequence += 1
        statistics.accepted += 1
        pending.append(LKConsoleEntry(sequence: sequence, event: event))
        pendingBytes += bytes
        scheduleLocked()
    }

    func scheduleLocked() {
        // 至多挂起一个 drain；持续输入不会为每条日志创建任务。
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in self?.drain() }
    }

    func drain() {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        pendingBytes = 0
        scheduled = false
        let nextFilter = requestedFilter
        let nextRevision = requestedRevision
        let isActive = active
        let immediately = immediatePublication
        immediatePublication = false
        lock.unlock()
        // 卸载后释放队列持有的快照，不做后续发布。
        guard isActive else { return }
        let changedFilter = revision != nextRevision
        filter = nextFilter
        revision = nextRevision
        for entry in batch {
            append(entry, filterIncrementally: !changedFilter)
        }
        // 查询扫描与 drain 串行，新输入在有界入口等待下一批，不会令结果永久失效。
        if changedFilter { rows = entries().filter { filter.includes($0.event) }.map(LKConsoleRow.init) }
        trimVisibleRows()
        publish(immediately: immediately)
    }

    /// 历史已在磁盘入口限量；一次回读不经过实时入口的 1,000 条限流。
    func restoreHistory(_ events: [LKLogEntry]) {
        lock.lock()
        guard active else { lock.unlock(); return }
        let batch = events.map { event in
            sequence += 1
            statistics.accepted += 1
            return LKConsoleEntry(sequence: sequence, event: event)
        }
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            lock.lock()
            let isActive = active
            lock.unlock()
            guard isActive else { return }
            for entry in batch {
                append(entry, filterIncrementally: true)
            }
            trimVisibleRows()
            publish(immediately: true)
        }
    }

    func append(_ entry: LKConsoleEntry, filterIncrementally: Bool) {
        // 单条已在入口验收；历史满时仅淘汰最旧记录。
        while count > 0, count == historyLimit || historyBytes + Int(entry.event.payloadByteCount) > historyByteLimit {
            historyBytes -= Int(ring[head]?.event.payloadByteCount ?? 0)
            ring[head] = nil
            head = (head + 1) % historyLimit
            count -= 1
            lock.lock()
            statistics.evicted += 1
            lock.unlock()
        }
        ring[(head + count) % historyLimit] = entry
        count += 1
        historyBytes += Int(entry.event.payloadByteCount)
        // 目录容量固定，已保存的包含/屏蔽值由发布时合并。
        if categoryDirectory.count < 512 { categoryDirectory.insert(entry.event.category) }
        if filterIncrementally, filter.includes(entry.event) { rows.append(LKConsoleRow(entry)) }
    }

    func trimVisibleRows() {
        // 删除已淘汰的列表索引；正文只保留在环形历史中。
        guard let oldest = ring[head]?.sequence else { rows.removeAll(); return }
        rows.removeAll { $0.sequence < oldest }
    }

    func entries() -> [LKConsoleEntry] {
        (0..<count).compactMap { ring[(head + $0) % historyLimit] }
    }

    func updateFilter(_ value: LKConsoleFilter) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        requestedFilter = value
        requestedRevision += 1
        immediatePublication = true
        scheduleLocked()
    }

    func observe(_ callback: ((LKConsoleSnapshot) -> Void)?) {
        lock.lock()
        observer = callback
        pendingSnapshot = nil
        // 重新显示时发布当前历史；隐藏后不保留页面闭包或 UI 快照。
        if callback != nil, active {
            immediatePublication = true
            scheduleLocked()
        }
        lock.unlock()
    }

    func publish(immediately: Bool = false) {
        let categories = categoryDirectory.union(filter.categories).union(filter.blocked).sorted()
        lock.lock()
        defer { lock.unlock() }
        // 仅过滤条件变更使扫描过期，新增日志不参与失效判断。
        guard active, observer != nil, requestedRevision == revision else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delay = lastPublication + Self.refreshInterval - now
        // 采集继续按小批次入库，只有 UI 快照按 5 秒节流；主动筛选/首次展示立即响应。
        if !immediately, delay > 0 {
            guard !publicationScheduled else { return }
            publicationScheduled = true
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.publicationScheduled = false
                self?.publish()
            }
            return
        }
        lastPublication = now
        pendingSnapshot = LKConsoleSnapshot(
            rows: Array(rows.reversed()),
            categories: categories,
            statistics: statistics,
            revision: revision,
            historyMessage: historyMessage,
        )
        // 主线程阻塞时替换最新快照，积压数量始终为一。
        guard !delivering else { return }
        delivering = true
        DispatchQueue.main.async { [weak self] in self?.deliver() }
    }

    func deliver() {
        lock.lock()
        let snapshot = pendingSnapshot
        pendingSnapshot = nil
        delivering = false
        let callback = active && snapshot?.revision == requestedRevision ? observer : nil
        lock.unlock()
        if let snapshot { callback?(snapshot) }
    }

    func close() {
        lock.lock()
        active = false
        pending.removeAll()
        pendingBytes = 0
        observer = nil
        pendingSnapshot = nil
        lock.unlock()
        // 队列中的旧工作先结束再释放历史，不与读取任务并发修改。
        queue.async { [weak self] in self?.releaseHistory() }
    }

    func releaseHistory() {
        ring.removeAll()
        rows.removeAll()
        categoryDirectory.removeAll()
        count = 0
        historyBytes = 0
    }
}
#endif
