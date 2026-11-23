// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Foundation
import LogCore
import SQLite3

/// 与页面分离的有界磁盘历史；隐藏时只保留 SQLite 小缓存和至多 1 MiB 的待写入批次。
final class LKConsoleHistory {
    // 快速卸载/重装也共用写入队列，避免新旧实例同时打开同一个数据库。
    private static let persistenceQueue = DispatchQueue(label: "com.baitu.logger.console.history", qos: .utility)
    let queue = LKConsoleHistory.persistenceQueue
    private let lock = NSLock()
    private let url: URL
    private let limit: Int
    private let byteLimit: Int
    private var pending: [LKLogEntry] = []
    private var pendingBytes = 0
    private var scheduled = false
    private var closed = false
    private var dropped = 0
    // 数据库和订阅目标仅在 queue 访问，回读与实时批次因此不会重复或交错。
    private var database: OpaquePointer?
    private var failure: Error?
    private weak var store: LKConsoleStore?
    private var reportedMessage: String?

    static var defaultURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LogKitConsole/history.sqlite")
    }

    init(url: URL = LKConsoleHistory.defaultURL, limit: Int = 5000, byteLimit: Int = 10 * 1024 * 1024) {
        self.url = url
        self.limit = max(1, limit)
        self.byteLimit = max(1, byteLimit)
        queue.async { [self] in
            do { try open() }
            catch { failure = error }
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func receive(_ event: LKLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        let bytes = Int(event.payloadByteCount)
        // 入口先限流再调度，日志洪峰不能堆积无界异步任务。
        guard event.category.utf16.count <= 256, bytes <= min(byteLimit, 1024 * 1024),
              pending.count < 1000, bytes <= 1024 * 1024 - pendingBytes else {
            dropped += 1
            return
        }
        pending.append(event)
        pendingBytes += bytes
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in self?.flush() }
    }

    /// 打开页面时先完成已有写入再回读，然后接续实时批次；仅弱引用页面的 Store。
    func attach(_ store: LKConsoleStore?) {
        queue.async { [self, weak store] in
            self.store = nil
            flush()
            self.store = store
            reportedMessage = nil
            guard let store else { return }
            do { try store.restoreHistory(read()) }
            catch { failure = error }
            reportStatus()
        }
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        queue.async { [self] in
            store = nil
            flush()
            sqlite3_close(database)
            database = nil
        }
    }

    /// SQLite 缓存、模式和语句的实际分配加入口载荷；磁盘文件大小不计入内存。
    func sampleMemory(_ completion: @escaping (Int) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(0); return }
            lock.lock()
            var bytes = pendingBytes + pending.capacity * MemoryLayout<LKLogEntry>.stride
            lock.unlock()
            if let database {
                for kind in [SQLITE_DBSTATUS_CACHE_USED, SQLITE_DBSTATUS_SCHEMA_USED, SQLITE_DBSTATUS_STMT_USED] {
                    var current: Int32 = 0
                    var high: Int32 = 0
                    if sqlite3_db_status(database, kind, &current, &high, 0) == SQLITE_OK { bytes += Int(current) }
                }
            }
            completion(bytes)
        }
    }

    private func open() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw databaseError() }
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path,
        )
        try execute(
            "PRAGMA journal_mode=DELETE; PRAGMA cache_size=-256; PRAGMA mmap_size=0; PRAGMA max_page_count=8192;",
        )
        try execute(
            "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, time REAL, level INTEGER, category BLOB, message BLOB, main INTEGER, bytes INTEGER)",
        )
    }

    private func flush() {
        lock.lock()
        let batch = pending
        pending.removeAll()
        pendingBytes = 0
        scheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }
        do {
            try execute("BEGIN IMMEDIATE")
            try insert(batch)
            // 双重预算：保留最新 5,000 条，并限制原文 UTF-16 总载荷，数据库页数另有硬限制。
            try execute("DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT \(limit))")
            try execute(
                "DELETE FROM events WHERE id IN (SELECT id FROM (SELECT id, SUM(bytes) OVER (ORDER BY id DESC) AS total FROM events) WHERE total > \(byteLimit))",
            )
            try execute("COMMIT")
            failure = nil
        } catch {
            try? execute("ROLLBACK")
            failure = error
        }
        // 磁盘不可写时仍允许当前页面看实时日志，同时显示历史不可用原因。
        for event in batch {
            store?.receive(event)
        }
        reportStatus()
    }

    private func insert(_ batch: [LKLogEntry]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO events(time,level,category,message,main,bytes) VALUES(?,?,?,?,?,?)",
            -1,
            &statement,
            nil,
        ) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for event in batch {
            sqlite3_reset(statement)
            sqlite3_bind_double(statement, 1, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, Int64(event.level.rawValue))
            // 使用含长度的 BLOB，原文中的 NUL 也能完整恢复。
            let category = Data(event.category.utf8)
            let message = Data(event.message.utf8)
            _ = category.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient) }
            _ = message.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), transient) }
            sqlite3_bind_int(statement, 5, event.isMainThread ? 1 : 0)
            sqlite3_bind_int64(statement, 6, Int64(event.payloadByteCount))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
        }
    }

    private func read() throws -> [LKLogEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT time,level,category,message,main FROM events ORDER BY id",
            -1,
            &statement,
            nil,
        ) == SQLITE_OK else { throw databaseError() }
        defer { sqlite3_finalize(statement) }
        var events: [LKLogEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return events }
            guard result == SQLITE_ROW else { throw databaseError() }
            let level = LKSeverity(rawValue: Int(sqlite3_column_int64(statement, 1))) ?? .info
            events.append(LKLogEntry(
                level: level,
                category: text(statement, column: 2),
                message: text(statement, column: 3),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                mainThread: sqlite3_column_int(statement, 4) != 0,
            ))
        }
    }

    private func text(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let bytes = sqlite3_column_blob(statement, column) else { return "" }
        return String(
            decoding: UnsafeRawBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))),
            as: UTF8.self,
        )
    }

    private func execute(_ sql: String) throws {
        guard database != nil, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func databaseError() -> Error {
        NSError(
            domain: "LogKitConsole.History",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: "历史日志暂不可用：\(String(cString: sqlite3_errmsg(database)))"],
        )
    }

    private func reportStatus() {
        lock.lock()
        let lost = dropped
        lock.unlock()
        let message = failure?.localizedDescription ?? (lost > 0 ? "历史入口已限流 \(lost) 条" : nil)
        guard message != reportedMessage else { return }
        reportedMessage = message
        store?.queue.async { [weak store] in store?.historyMessage = message }
    }
}
#endif
