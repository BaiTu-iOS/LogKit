// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import LogCore
import UIKit

/// 持有一条已接受原文；淘汰历史不会关闭详情。每页最多布局 16K UTF-16 单元。
final class LKConsoleDetailController: UIViewController {
    private let event: LKLogEntry
    private let keyword: String
    private let textView = UITextView()
    private let mode = UISegmentedControl(items: ["原文", "格式化"])
    private let pageLabel = UILabel()
    private var formatted: NSAttributedString?
    private var requestID: UUID?
    private var page = 0
    private let pageSize = 16 * 1024
    private var ranges: [NSRange] = []

    var estimatedBytes: Int {
        Int(event.payloadByteCount) + (formatted?.length ?? 0) * 2
            + (textView.attributedText?.length ?? 0) * 2 + ranges.capacity * MemoryLayout<NSRange>.stride
    }

    init(event: LKLogEntry, keyword: String) {
        self.event = event
        self.keyword = keyword
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    deinit { LKConsoleFormatter.shared.cancel(requestID) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = event.category
        view.backgroundColor = .systemBackground
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action: #selector(handleModeButtonEvent), for: .valueChanged)
        navigationItem.titleView = mode
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "复制/分享",
            style: .plain,
            target: self,
            action: #selector(handleCopyButtonEvent),
        )
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .systemBackground
        textView.adjustsFontForContentSizeCategory = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        toolbarItems = [.init(title: "上一页", style: .plain, target: self, action: #selector(handlePreviousButtonEvent)),
                        .init(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                        .init(customView: pageLabel),
                        .init(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                        .init(title: "下一页", style: .plain, target: self, action: #selector(handleNextButtonEvent))]
        rebuildPages()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        LKConsoleFormatter.shared.cancel(requestID)
        mode.isEnabled = true
        if formatted == nil { mode.selectedSegmentIndex = 0 }
    }

    private func rebuildPages() {
        let source = (formatted?.string ?? event.message) as NSString
        ranges.removeAll(keepingCapacity: true)
        var offset = 0
        while offset < source.length {
            var length = min(pageSize, source.length - offset)
            // 分页不能切开代理对；不为超长组合字符扫描整篇文本。
            let last = source.character(at: offset + length - 1)
            if offset + length < source.length, (0xD800...0xDBFF).contains(last) { length -= 1 }
            ranges.append(NSRange(location: offset, length: length))
            offset += length
        }
        if ranges.isEmpty { ranges = [NSRange(location: 0, length: 0)] }
        page = 0
        renderPage()
    }

    private func renderPage() {
        let range = ranges[page]
        if let formatted {
            textView.attributedText = formatted.attributedSubstring(from: range)
        } else {
            let text = (event.message as NSString).substring(with: range)
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: UIColor.label,
                ],
            )
            LKConsoleFormatter.highlight(keyword, in: attributed)
            textView.attributedText = attributed
        }
        pageLabel.text = "\(page + 1) / \(ranges.count)"
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    @objc
    private func handleModeButtonEvent() {
        LKConsoleFormatter.shared.cancel(requestID)
        guard mode.selectedSegmentIndex == 1 else { formatted = nil; rebuildPages(); return }
        mode.isEnabled = false
        requestID = LKConsoleFormatter.shared.request(text: event.message, keyword: keyword) { [weak self] result in
            guard let self else { return }
            mode.isEnabled = true
            formatted = result
            mode.selectedSegmentIndex = result == nil ? 0 : 1
            rebuildPages()
            if result == nil { showMessage("内容不是标准 JSON，或超过格式化预算。已保留完整原文。") }
        }
    }

    @objc
    private func handlePreviousButtonEvent() {
        guard page > 0 else { return }
        page -= 1
        renderPage()
    }

    @objc
    private func handleNextButtonEvent() {
        guard page + 1 < ranges.count else { return }
        page += 1
        renderPage()
    }

    @objc
    private func handleCopyButtonEvent(_ sender: UIBarButtonItem) {
        let sheet = UIAlertController(title: "完整内容", message: "复制与分享包含全部页面", preferredStyle: .actionSheet)
        sheet
            .addAction(UIAlertAction(title: "复制原文", style: .default) { [weak self] _ in
            UIPasteboard.general.string = self?.event.message
            })
        if let formatted {
            sheet
                .addAction(UIAlertAction(title: "复制格式化内容", style: .default) { _ in
                UIPasteboard.general.string = formatted.string
                })
        }
        sheet.addAction(UIAlertAction(title: "分享原文", style: .default) { [weak self] _ in self?.share(sender) })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = sender
        present(sheet, animated: true)
    }

    private func share(_ sender: UIBarButtonItem) {
        let share = UIActivityViewController(activityItems: [event.message], applicationActivities: nil)
        share.popoverPresentationController?.barButtonItem = sender
        present(share, animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: "日志详情", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
#endif
