// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import UIKit

/// 跨安装会话共享一个工作槽和一个最新请求，取消不会启动额外的系统 JSON 解析。
final class LKConsoleFormatter {
    static let shared = LKConsoleFormatter()
    static let inputLimit = 256 * 1024
    private let lock = NSLock()
    let queue = DispatchQueue(label: "com.baitu.logger.console.format", qos: .utility)
    private var pending: (UUID, String, String, (NSAttributedString?) -> Void)?
    private var currentID: UUID?
    private var working = false
    private var pendingDelivery: (UUID, NSAttributedString?, (NSAttributedString?) -> Void)?
    private var delivering = false
    private var workingBytes = 0

    func request(text: String, keyword: String, completion: @escaping (NSAttributedString?) -> Void) -> UUID {
        let identifier = UUID()
        lock.lock()
        currentID = identifier
        pending = (identifier, text, keyword, completion)
        pendingDelivery = nil
        let shouldStart = !working
        working = true
        lock.unlock()
        if shouldStart { queue.async { [weak self] in self?.drain() } }
        return identifier
    }

    func cancel(_ identifier: UUID?) {
        lock.lock()
        defer { lock.unlock() }
        // 老页面退出不能取消新页面的格式化。
        guard currentID == identifier else { return }
        currentID = nil
        pending = nil
        pendingDelivery = nil
    }

    private func drain() {
        while true {
            lock.lock()
            let request = pending
            pending = nil
            workingBytes = (request?.1.utf16.count ?? 0) * 2
            if request == nil { working = false }
            lock.unlock()
            guard let (identifier, text, keyword, completion) = request else { return }
            let output = autoreleasepool { format(text, keyword: keyword, identifier: identifier) }
            lock.lock()
            workingBytes = 0
            if currentID == identifier {
                pendingDelivery = (identifier, output, completion)
                if !delivering {
                    delivering = true
                    DispatchQueue.main.async { [weak self] in self?.deliver() }
                }
            }
            lock.unlock()
        }
    }

    private func deliver() {
        lock.lock()
        let value = pendingDelivery
        pendingDelivery = nil
        delivering = false
        let valid = value?.0 == currentID
        lock.unlock()
        if valid, let value { value.2(value.1) }
    }

    /// 格式化输入及待交付文本估算；JSON 解析器的瞬时分配不在此采样中。
    var estimatedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return workingBytes + (pending?.1.utf16.count ?? 0) * 2 + (pendingDelivery?.1?.length ?? 0) * 2
    }

    private func isCurrent(_ identifier: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentID == identifier
    }

    private func format(_ text: String, keyword: String, identifier: UUID) -> NSAttributedString? {
        // 手动格式化也不能绕过硬上限；过深或过多节点在系统解析前拒绝。
        guard isCurrent(identifier), Self.canFormat(text), let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .fragmentsAllowed],
              ),
              pretty.count <= 512 * 1024, let string = String(data: pretty, encoding: .utf8),
              isCurrent(identifier) else { return nil }
        let result = NSMutableAttributedString(
            string: string,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: UIColor.label,
            ],
        )
        // JSON 已由系统验证；正则只识别独立 token，不推测嵌套结构。
        let pattern = #""(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|\b(?:true|false|null)\b"#
        guard let tokens = try? NSRegularExpression(pattern: pattern) else { return result }
        let full = NSRange(location: 0, length: (string as NSString).length)
        tokens.enumerateMatches(in: string, range: full) { token, _, stop in
            guard self.isCurrent(identifier), let token else { stop.pointee = true; return }
            let value = (string as NSString).substring(with: token.range)
            let color: UIColor = value.hasPrefix("\"") ? .systemGreen : .systemOrange
            result.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        Self.highlight(keyword, in: result)
        return isCurrent(identifier) ? result : nil
    }

    static func canFormat(_ text: String) -> Bool {
        // UTF-16 长度先做廉价检查，再限制 UTF-8 输入与结构复杂度。
        guard (text as NSString).length <= inputLimit else { return false }
        let bytes = Array(text.utf8)
        guard bytes.count <= inputLimit else { return false }
        var depth = 0
        var nodes = 0
        var quoted = false
        var escaped = false
        for byte in bytes {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 {
                quoted = true
                nodes += 1
            } else if byte == 123 || byte == 91 {
                depth += 1
                nodes += 1
            } else if byte == 125 || byte == 93 {
                depth -= 1
            } else if byte == 44 { nodes += 1 }
            // 限制漂亮打印的缩进放大与解析对象数量，语法正确性仍交给系统。
            if depth > 64 || nodes > 8192 { return false }
        }
        return true
    }

    static func highlight(_ keyword: String, in text: NSMutableAttributedString) {
        guard !keyword.isEmpty else { return }
        let source = text.string as NSString
        var start = 0
        while start < source.length {
            let found = source.range(
                of: keyword,
                options: [.caseInsensitive, .literal],
                range: NSRange(location: start, length: source.length - start),
            )
            guard found.location != NSNotFound, found.length > 0 else { break }
            text.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: found)
            start = NSMaxRange(found)
        }
    }
}
#endif
