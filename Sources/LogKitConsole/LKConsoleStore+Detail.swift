// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import Foundation
import LogCore

extension LKConsoleStore {
    func event(sequence: UInt64, completion: @escaping (LKLogEntry?) -> Void) {
        queue.async { [weak self] in
            let event = self?.entries().first { $0.sequence == sequence }?.event
            DispatchQueue.main.async { completion(event) }
        }
    }
}
#endif
