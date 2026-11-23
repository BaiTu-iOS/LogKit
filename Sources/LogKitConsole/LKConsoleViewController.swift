// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import LogCore
import UIKit

/// 列表持有预览和稳定序号；完整正文按需从 Store 取得。
final class LKConsoleViewController: UITableViewController, UISearchResultsUpdating {
    let store: LKConsoleStore
    var filter = LKConsoleFilter.load()
    var snapshot: LKConsoleSnapshot?
    var rows: [LKConsoleRow] = []
    var onClose: (() -> Void)?
    var searchTimer: Timer?
    var deferredSnapshot: LKConsoleSnapshot?
    var scrolling = false
    var paused = false
    var openingDetail = false
    var newCount = 0
    let statusLabel = UILabel()
    let memoryLabel = UILabel()
    let search = UISearchController(searchResultsController: nil)
    lazy var followButton = UIBarButtonItem(
        title: "最新",
        style: .plain,
        target: self,
        action: #selector(handleFollowButtonEvent),
    )
    lazy var pauseButton = UIBarButtonItem(
        title: "暂停刷新",
        style: .plain,
        target: self,
        action: #selector(handlePauseButtonEvent),
    )
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(store: LKConsoleStore) {
        self.store = store
        super.init(style: .plain)
        // 跟随属于本次浏览会话，旧版本持久化的停止跟随不应影响重新打开。
        filter.followsTail = true
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "实时日志"
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        memoryLabel.font = .preferredFont(forTextStyle: .caption2)
        memoryLabel.adjustsFontForContentSizeCategory = true
        memoryLabel.adjustsFontSizeToFitWidth = true
        memoryLabel.minimumScaleFactor = 0.7
        memoryLabel.text = "中控内存采样中…"
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, memoryLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        navigationItem.titleView = titleStack
        view.backgroundColor = .systemBackground
        tableView.estimatedRowHeight = 84
        tableView.rowHeight = UITableView.automaticDimension
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索完整原文"
        search.searchBar.text = filter.keyword
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(handleCloseButtonEvent),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "筛选",
            style: .plain,
            target: self,
            action: #selector(handleFilterButtonEvent),
        )
        toolbarItems = [pauseButton, .init(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), followButton]
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.frame.size.height = 72
        tableView.tableHeaderView = statusLabel
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(handleRefreshButtonEvent), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scrolling = false
        navigationController?.setToolbarHidden(false, animated: animated)
        if !paused { resumeUpdates() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        store.observe(nil)
        deferredSnapshot = nil
        if searchTimer?.isValid == true { applyFilter() }
        searchTimer?.invalidate()
    }

    func resumeUpdates() {
        store.observe { [weak self] snapshot in self?.apply(snapshot) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if filter.followsTail { scrollToLatest() }
    }

    /// 关闭采集时同步释放列表预览和待展示快照。
    func releaseResources() {
        searchTimer?.invalidate()
        searchTimer = nil
        store.observe(nil)
        rows.removeAll()
        snapshot = nil
        deferredSnapshot = nil
        if isViewLoaded { tableView.reloadData() }
    }

    func apply(_ value: LKConsoleSnapshot) {
        // 拖动及惯性减速期间只替换一个待展示快照，不修改表格或强制布局。
        if scrolling || tableView.isTracking || tableView.isDragging || tableView.isDecelerating {
            deferredSnapshot = value
            return
        }
        let anchor = tableView.indexPathsForVisibleRows?.first
        let anchorID = anchor.flatMap { rows.indices.contains($0.row) ? rows[$0.row].sequence : nil }
        let offset = anchor.map { tableView.rectForRow(at: $0).minY - tableView.contentOffset.y } ?? 0
        let newest = rows.first?.sequence ?? 0
        let appended = value.rows.count(where: { $0.sequence > newest })
        let changed = snapshot?.revision != value.revision || rows.map(\.sequence) != value.rows.map(\.sequence)
        rows = value.rows
        snapshot = value
        if changed {
            // 每 5 秒一次无动画替换，避免批量插入的异步布局覆盖“滚到最新”的位置。
            UIView.performWithoutAnimation {
                tableView.reloadData()
                tableView.layoutIfNeeded()
                restorePosition(anchorID: anchorID, offset: offset, appended: appended)
            }
        }
        let stats = value.statistics
        statusLabel
            .text =
            "显示 \(rows.count) 条 · 每 5 秒更新\n过载 \(stats.overloaded) · 超限 \(stats.oversized) · 淘汰 \(stats.evicted)" +
            (value.historyMessage.map { "\n\($0)" } ?? "")
        refreshControl?.endRefreshing()
    }

    private func restorePosition(anchorID: UInt64?, offset: CGFloat, appended: Int) {
        if filter.followsTail { scrollToLatest(); return }
        newCount += appended
        followButton.title = newCount > 0 ? "新增 \(newCount) · 最新" : "最新"
        // 淘汰锚点时回退到最早的现存日志，避免使用已失效的行号。
        guard let anchorID else { return }
        guard let index = rows.firstIndex(where: { $0.sequence == anchorID }) else {
            if !rows.isEmpty { tableView.scrollToRow(
                at: IndexPath(row: rows.count - 1, section: 0),
                at: .bottom,
                animated: false,
            ) }
            followButton.title = "旧日志已淘汰 · 最新"
            return
        }
        tableView.contentOffset.y = tableView.rectForRow(at: IndexPath(row: index, section: 0)).minY - offset
    }

    func scrollToLatest() {
        guard !rows.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Log") ?? UITableViewCell(
            style: .subtitle,
            reuseIdentifier: "Log",
        )
        let row = rows[indexPath.row]
        cell.textLabel?.font = .preferredFont(forTextStyle: .caption1)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        let level = LKConsoleFilter.levelNames.indices.contains(row.level) ? LKConsoleFilter.levelNames[row.level] : "Unknown"
        cell.textLabel?.text = "\(timeFormatter.string(from: row.timestamp)) [\(level)] \(row.category) · \(row.isMainThread ? "主线程" : "后台线程")"
        let levelColor: UIColor = switch LKSeverity(rawValue: row.level) {
        case .verbose: .secondaryLabel
        case .debug: .systemBlue
        case .info: .systemGreen
        case .warning: .systemOrange
        case .error: .systemRed
        case .fatal: .systemPurple
        default: .secondaryLabel
        }
        // 等级小字采用系统高对比度动态配色，并保留文字，避免仅靠颜色识别。
        cell.textLabel?.textColor = UIColor { traits in
            levelColor.resolvedColor(with: UITraitCollection(traitsFrom: [
                traits,
                UITraitCollection(accessibilityContrast: .high),
            ]))
        }
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .footnote)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.numberOfLines = 3
        cell.detailTextLabel?.text = row.preview
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !openingDetail else { return }
        filter.followsTail = false
        openingDetail = true
        let sequence = rows[indexPath.row].sequence
        store.event(sequence: sequence) { [weak self] event in
            guard let self else { return }
            openingDetail = false
            guard view.window != nil, navigationController?.topViewController === self else { return }
            guard let event else { showMessage("这条日志已被历史缓存淘汰"); return }
            navigationController?.pushViewController(
                LKConsoleDetailController(event: event, keyword: filter.keyword),
                animated: true,
            )
        }
    }

    override func scrollViewWillBeginDragging(_: UIScrollView) {
        // 手动浏览即停止跟随，同时暂停拖动及随后减速期间的表格变更。
        scrolling = true
        filter.followsTail = false
    }

    override func scrollViewDidScroll(_: UIScrollView) {
        // 仅响应本次手势，程序恢复阅读锚点时不能误清未读数。
        if scrolling { updateFollowingPosition() }
    }

    private func updateFollowingPosition() {
        let firstRowY = rows.isEmpty ? 0 : tableView.rectForRow(at: IndexPath(row: 0, section: 0)).minY
        filter.followsTail = tableView.contentOffset.y + tableView.adjustedContentInset.top <= firstRowY + 1
        if filter.followsTail {
            newCount = 0
            followButton.title = "最新"
        }
    }

    override func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishScrolling() }
    }

    override func scrollViewDidEndDecelerating(_: UIScrollView) {
        finishScrolling()
    }

    private func finishScrolling() {
        updateFollowingPosition()
        scrolling = false
        guard let value = deferredSnapshot else { return }
        deferredSnapshot = nil
        apply(value)
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchTimer?.invalidate()
        filter.setKeyword(searchController.searchBar.text ?? "")
        searchTimer = Timer
            .scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in self?.applyFilter() }
    }

    func applyFilter() {
        filter.save()
        store.updateFilter(filter)
    }

    func showMessage(_ text: String) {
        let alert = UIAlertController(title: "日志中控", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
#endif
