// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import LogCore
import UIKit

/// 应用内日志中控入口。所有生命周期方法必须在主线程调用。
@objc(LKLogConsole)
public final class LKLogConsole: NSObject, UIAdaptivePresentationControllerDelegate, UINavigationControllerDelegate {
    private var store: LKConsoleStore?
    private var subscription: LKLogObservation?
    private var history: LKConsoleHistory?
    /// 隐藏时仅限量写磁盘历史，不保留页面和内存历史。
    private var minimumLevel: LKSeverity?
    private var navigation: UINavigationController?
    private var window: LKConsoleWindow?
    private weak var previousKeyWindow: UIWindow?
    private var dismissing = false
    private(set) var memoryTimer: Timer?
    private var memorySampling = false

    /// 折叠后的一次性 60 秒计时器；展开或隐藏时撤销。
    private(set) var entranceTimer: Timer?

    /// 进程共享实例，最多在一个 Scene 中显示。
    @objc public static let shared = LKLogConsole()

    /// 是否允许打开中控并记录有界磁盘历史。
    @objc public var isInstalled: Bool {
        minimumLevel != nil
    }

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDisconnect),
            name: UIScene.didDisconnectNotification,
            object: nil,
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        entranceTimer?.invalidate()
        memoryTimer?.invalidate()
    }

    /// 幂等启用中控并保存最近日志到本机缓存目录，不改变日志输出端的等级。
    @objc
    public func install() {
        install(minimumLevel: .verbose)
    }

    /// 幂等安装。已安装时保留原采集阈值；更换阈值先卸载。
    /// - Parameter minimumLevel: 中控独立采集的最低等级。
    @objc
    public func install(minimumLevel: LKSeverity) {
        precondition(Thread.isMainThread, "Console lifecycle requires the main thread")
        guard self.minimumLevel == nil else { return }
        self.minimumLevel = minimumLevel
        let history = LKConsoleHistory()
        self.history = history
        subscription = LKLogCenter.shared()
            .observe(minimumLevel: minimumLevel) { [weak history] event in history?.receive(event) }
    }

    /// 在宿主所属 Scene 展开日志，回读最近历史并接续实时日志；筛选偏好保留。
    /// - Parameter presenter: 已进入窗口的宿主控制器，不占用它的模态展示。
    /// - Returns: 是否已显示或开始展开；未安装、正在折叠或已显示在其他 Scene 时返回 false。
    @objc
    @discardableResult
    public func show(from presenter: UIViewController) -> Bool {
        precondition(Thread.isMainThread, "Console lifecycle requires the main thread")
        guard isInstalled, !dismissing, let scene = presenter.viewIfLoaded?.window?.windowScene else { return false }
        if let window {
            guard window.windowScene === scene else { return false }
            return expand()
        }
        let window = LKConsoleWindow(scene: scene)
        window.entrance.addTarget(self, action: #selector(handleEntranceButtonEvent), for: .touchUpInside)
        self.window = window
        return expand()
    }

    private func expand() -> Bool {
        guard let window, let root = window.rootViewController, isInstalled, !dismissing else { return false }
        if navigation?.presentingViewController != nil { return true }
        guard root.presentedViewController == nil else { return false }
        entranceTimer?.invalidate()
        entranceTimer = nil
        let store = LKConsoleStore(filter: .load())
        self.store = store
        history?.attach(store)
        let controller = LKConsoleViewController(store: store)
        controller.onClose = { [weak self] in self?.collapse() }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.delegate = self
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.largestUndimmedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
        self.navigation = navigation
        previousKeyWindow = window.windowScene?.windows.first { $0.isKeyWindow && $0 !== window }
        window.entrance.isHidden = true
        window.makeKeyAndVisible()
        root.present(navigation, animated: true)
        navigation.presentationController?.delegate = self
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sampleMemory() }
        sampleMemory()
        return true
    }

    /// 释放内存日志和页面，只保留入口；60 秒未点击自动隐藏。磁盘历史继续限量写入，主线程调用。
    @objc
    public func collapse() {
        precondition(Thread.isMainThread, "Console lifecycle requires the main thread")
        guard let window, let root = window.rootViewController, root.presentedViewController != nil,
              !dismissing else { return }
        dismissing = true
        stopCollecting()
        navigation?.view.endEditing(true)
        // 从浮层根节点关闭整条展示链，详情分享面板也随之收起。
        root.dismiss(animated: true) { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            finishCollapse()
        }
    }

    private func finishCollapse() {
        dismissing = false
        stopCollecting()
        navigation = nil
        window?.entrance.isHidden = false
        restoreHostWindow()
        entranceTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.hide() }
        entranceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCollecting() {
        memoryTimer?.invalidate()
        memoryTimer = nil
        memorySampling = false
        // 先关闭页面入口，磁盘的在途批次也不能重新填充旧页面。
        store?.close()
        history?.attach(nil)
        store = nil
        (navigation?.viewControllers.first as? LKConsoleViewController)?.releaseResources()
    }

    private func sampleMemory() {
        // 至多一个采样任务；滑动时不更新提示文字，折叠后立即停止。
        guard !memorySampling, let store, let history, let navigation,
              let list = navigation.viewControllers.first as? LKConsoleViewController, !list.scrolling else { return }
        memorySampling = true
        store.sampleMemory { [weak self, weak history, weak navigation] storeBytes in
            guard let history else { return }
            history.sampleMemory { [weak self, weak navigation] historyBytes in
                DispatchQueue.main.async { [weak self, weak navigation] in
                    guard let self, let navigation, self.navigation === navigation, memoryTimer != nil else { return }
                    memorySampling = false
                    let list = navigation.viewControllers.first as? LKConsoleViewController
                    let scrollingView = navigation.topViewController?.viewIfLoaded?.subviews
                        .compactMap { $0 as? UIScrollView }.first
                    guard list?.scrolling != true, scrollingView?.isDragging != true,
                          scrollingView?.isDecelerating != true else { return }
                    let ui = LKConsoleMemory.rows(list?.rows ?? []) + LKConsoleMemory
                        .rows(list?.deferredSnapshot?.rows ?? [])
                        + navigation.viewControllers.compactMap { $0 as? LKConsoleDetailController }
                            .reduce(0) { $0 + $1.estimatedBytes }
                    let text = LKConsoleMemory
                        .description(bytes: storeBytes + historyBytes + ui + LKConsoleFormatter.shared.estimatedBytes)
                    list?.memoryLabel.text = text
                    list?.memoryLabel.accessibilityLabel = "实时日志中控数据内存估算，\(text)"
                }
            }
        }
    }

    private func restoreHostWindow() {
        guard let window, window.isKeyWindow else { return }
        let host = previousKeyWindow.flatMap { !$0.isHidden && $0.windowScene === window.windowScene ? $0 : nil }
            ?? window.windowScene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }
        host?.makeKey()
    }

    /// 清空内存日志并移除全部界面；仍记录有界磁盘历史，可摇一摇重新打开。主线程调用。
    @objc
    public func hide() {
        precondition(Thread.isMainThread, "Console lifecycle requires the main thread")
        entranceTimer?.invalidate()
        entranceTimer = nil
        stopCollecting()
        window?.endEditing(true)
        window?.rootViewController?.dismiss(animated: false)
        restoreHostWindow()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        navigation = nil
        previousKeyWindow = nil
        dismissing = false
    }

    /// 幂等卸载，移除浮层与采集器，不改变日志输出端。主线程调用。
    @objc
    public func uninstall() {
        precondition(Thread.isMainThread, "Console lifecycle requires the main thread")
        minimumLevel = nil
        hide()
        subscription?.cancel()
        subscription = nil
        history?.close()
        history = nil
    }

    /// 下拉关闭系统浮层后回到悬浮入口。
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === navigation else { return }
        finishCollapse()
    }

    /// 所有导航页面均提供折叠操作，详情和筛选页面也可直接收起。
    public func navigationController(
        _: UINavigationController,
        willShow viewController: UIViewController,
        animated _: Bool,
    ) {
        viewController.navigationItem.leftItemsSupplementBackButton = true
        viewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "折叠",
            style: .plain,
            target: self,
            action: #selector(handleCollapseButtonEvent),
        )
    }

    @objc
    private func handleEntranceButtonEvent() {
        _ = expand()
    }

    @objc
    private func handleCollapseButtonEvent() {
        collapse()
    }

    @objc
    private func handleSceneDisconnect(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
        hide()
    }
}
#endif
