// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Darwin
import Foundation
import LogCore
import ObjectiveC

/// 统计中控持有的数据；UIKit、解析器和压缩器的瞬时分配只能反映在进程物理占用中。
enum LKConsoleMemory {
    static func rows(_ rows: [LKConsoleRow]) -> Int {
        rows.capacity * MemoryLayout<LKConsoleRow>.stride + rows.reduce(0) {
            $0 + ($1.preview.utf16.count + $1.category.utf16.count) * 2
        }
    }

    static func processFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    static func description(bytes: Int) -> String {
        let module = String(format: "%.2f MiB", Double(bytes) / 1_048_576)
        let process = processFootprint().map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "不可用"
        return "数据≈\(module) · 进程 \(process)"
    }
}

extension LKConsoleStore {
    /// 只在各自数据队列采样，不在主线程等待入库或筛选。
    func sampleMemory(_ completion: @escaping (Int) -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(0); return }
            lock.lock()
            let inlet = pendingBytes + pending.capacity * MemoryLayout<LKConsoleEntry>.stride
                + pending.count * class_getInstanceSize(LKLogEntry.self)
            let publication = LKConsoleMemory.rows(pendingSnapshot?.rows ?? [])
            lock.unlock()
            let history = historyBytes + ring.capacity * MemoryLayout<LKConsoleEntry?>.stride
                + count * class_getInstanceSize(LKLogEntry.self)
            let categories = categoryDirectory.reduce(0) { $0 + $1.utf16.count * 2 }
            completion(inlet + publication + history + categories + LKConsoleMemory.rows(rows))
        }
    }
}
#endif
