// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import UIKit

/// 同维度 OR、跨维度 AND；屏蔽页始终包含已保存但未再次出现的模块。
final class LKConsoleFilterController: UITableViewController, UISearchResultsUpdating {
    private var filter: LKConsoleFilter
    private let categories: [String]
    private var candidates: [String] = []
    private var blocked: [String] = []
    private let search = UISearchController(searchResultsController: nil)
    var onChange: ((LKConsoleFilter) -> Void)?

    init(filter: LKConsoleFilter, categories: [String]) {
        self.filter = filter
        self.categories = Array(Set(categories).union(filter.categories).union(filter.blocked)).sorted()
        super.init(style: .insetGrouped)
        updateCandidates("")
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "筛选与屏蔽"
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "查找 category，前缀优先"
        navigationItem.searchController = search
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "重置",
            style: .plain,
            target: self,
            action: #selector(handleResetButtonEvent),
        )
        navigationController?.setToolbarHidden(true, animated: false)
        definesPresentationContext = true
    }

    override func numberOfSections(in _: UITableView) -> Int {
        4
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: LKConsoleFilter.levelNames.count
        case 1: 4
        case 2: candidates.count
        default: blocked.count
        }
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["等级（未选择表示全部）", "时间范围（本机时区，仅查询已保留的历史）", "包含 category（未选择表示全部，左滑屏蔽）", "已屏蔽 category（点击取消屏蔽）"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 { return timeCell(row: indexPath.row) }
        let cell = tableView.dequeueReusableCell(withIdentifier: "Filter") ?? UITableViewCell(
            style: .default,
            reuseIdentifier: "Filter",
        )
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        let selected: Bool
        switch indexPath.section {
        case 0:
            cell.textLabel?.text = LKConsoleFilter.levelNames[indexPath.row]
            selected = filter.levels.contains(indexPath.row)
        case 2:
            cell.textLabel?.text = candidates[indexPath.row]
            selected = filter.categories.contains(candidates[indexPath.row])
        default:
            cell.textLabel?.text = blocked[indexPath.row]
            selected = true
        }
        cell.accessoryType = selected ? .checkmark : .none
        cell.accessibilityValue = selected ? "已选择" : "未选择"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // 时间由开关/日期控件处理，点行本身不改变模块选择。
        guard indexPath.section != 1 else { return }
        switch indexPath.section {
        case 0:
            if !filter.levels.insert(indexPath.row).inserted { filter.levels.remove(indexPath.row) }
        case 2:
            let category = candidates[indexPath.row]
            if filter.categories.contains(category) { filter.categories.remove(category) }
            else if filter.categories.count < 256 { filter.categories.insert(category) }
        default:
            filter.blocked.remove(blocked[indexPath.row])
        }
        changed()
    }

    override func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2 else { return nil }
        let category = candidates[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "屏蔽") { [weak self] _, _, completion in
            guard let self, filter.blocked.count < 256 else { completion(false); return }
            filter.blocked.insert(category)
            changed()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func updateSearchResults(for searchController: UISearchController) {
        updateCandidates(searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    private func updateCandidates(_ keyword: String) {
        let available = categories.filter { !filter.blocked.contains($0) }
        let matching = available.filter { keyword.isEmpty || $0.localizedCaseInsensitiveContains(keyword) }
        candidates = matching.sorted {
            let leftPrefix = $0.lowercased().hasPrefix(keyword.lowercased())
            let rightPrefix = $1.lowercased().hasPrefix(keyword.lowercased())
            return leftPrefix != rightPrefix ? leftPrefix : $0 < $1
        }
        blocked = filter.blocked.sorted()
    }

    private func changed() {
        filter.save()
        onChange?(filter)
        updateCandidates(search.searchBar.text ?? "")
        tableView.reloadData()
    }

    private func timeCell(row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let isStart = row < 2
        let date = isStart ? filter.startDate : filter.endDate
        cell.selectionStyle = .none
        if row.isMultiple(of: 2) {
            cell.textLabel?.text = isStart ? "仅看此时间之后" : "仅看此时间之前"
            let toggle = UISwitch()
            toggle.tag = isStart ? 0 : 1
            toggle.isOn = date != nil
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.addTarget(self, action: #selector(handleTimeToggleButtonEvent), for: .valueChanged)
            cell.accessoryView = toggle
        } else {
            let picker = UIDatePicker()
            picker.datePickerMode = .dateAndTime
            picker.preferredDatePickerStyle = .compact
            picker.tag = isStart ? 0 : 1
            picker.date = date ?? Date()
            picker.isEnabled = date != nil
            picker.minimumDate = isStart ? nil : filter.startDate
            picker.maximumDate = isStart ? filter.endDate : nil
            picker.accessibilityLabel = isStart ? "起始时间" : "结束时间"
            picker.addTarget(self, action: #selector(handleTimePickerButtonEvent), for: .valueChanged)
            picker.sizeToFit()
            cell.textLabel?.text = isStart ? "起始" : "结束"
            cell.accessoryView = picker
        }
        return cell
    }

    @objc
    private func handleTimeToggleButtonEvent(_ sender: UISwitch) {
        // 打开边界时保证时间范围有效，关闭则恢复该方向不限时间。
        if sender.tag == 0 { filter.startDate = sender.isOn ? min(Date(), filter.endDate ?? Date()) : nil }
        else { filter.endDate = sender.isOn ? max(Date(), filter.startDate ?? Date()) : nil }
        changed()
    }

    @objc
    private func handleTimePickerButtonEvent(_ sender: UIDatePicker) {
        if sender.tag == 0 { filter.startDate = sender.date }
        else { filter.endDate = sender.date }
        filter.save()
        onChange?(filter)
        // 不重建正在操作的 compact picker，保持系统日期弹层和滚轮连续可操作。
        let otherRow = sender.tag == 0 ? 3 : 1
        let other = tableView.cellForRow(at: IndexPath(row: otherRow, section: 1))?.accessoryView as? UIDatePicker
        if sender.tag == 0 { other?.minimumDate = sender.date }
        else { other?.maximumDate = sender.date }
    }

    @objc
    private func handleResetButtonEvent() {
        filter.categories.removeAll()
        filter.blocked.removeAll()
        filter.levels.removeAll()
        filter.startDate = nil
        filter.endDate = nil
        changed()
    }
}
#endif
