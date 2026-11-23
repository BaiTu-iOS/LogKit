// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import UIKit

extension LKConsoleViewController {
    @objc
    func handleCloseButtonEvent() {
        onClose?()
    }

    @objc
    func handleFollowButtonEvent() {
        filter.followsTail = true
        filter.save()
        newCount = 0
        followButton.title = "最新"
        scrollToLatest()
        handleRefreshButtonEvent()
    }

    @objc
    func handlePauseButtonEvent() {
        paused.toggle()
        pauseButton.title = paused ? "继续刷新" : "暂停刷新"
        if paused {
            deferredSnapshot = nil
            store.observe(nil)
        } else { resumeUpdates() }
    }

    @objc
    func handleRefreshButtonEvent() {
        // 手动刷新只读取内存；即使暂停也允许取一次快照。
        store.observe { [weak self] value in
            self?.apply(value)
            if self?.paused == true { self?.store.observe(nil) }
        }
    }

    @objc
    func handleFilterButtonEvent() {
        search.isActive = false
        let controller = LKConsoleFilterController(filter: filter, categories: snapshot?.categories ?? [])
        controller.onChange = { [weak self] filter in
            self?.filter = filter
            self?.applyFilter()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
#endif
