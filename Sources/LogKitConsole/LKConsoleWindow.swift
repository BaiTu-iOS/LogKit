// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import UIKit

/// 当前 Scene 的日志浮层；透明区域将触摸交还给业务窗口。
final class LKConsoleWindow: LKLogConsoleShakeWindow {
    /// 折叠时唯一可交互的入口。
    let entrance = UIButton(type: .system)
    private var positionedEntrance = false

    init(scene: UIWindowScene) {
        super.init(windowScene: scene)
        frame = scene.coordinateSpace.bounds
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        rootViewController = controller
        entrance.setTitle("日志", for: .normal)
        entrance.setTitleColor(.white, for: .normal)
        entrance.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        entrance.titleLabel?.adjustsFontForContentSizeCategory = true
        entrance.backgroundColor = .systemBlue
        entrance.layer.cornerRadius = 24
        entrance.layer.shadowColor = UIColor.black.cgColor
        entrance.layer.shadowOpacity = 0.2
        entrance.layer.shadowRadius = 6
        entrance.layer.shadowOffset = CGSize(width: 0, height: 2)
        entrance.accessibilityLabel = "展开实时日志"
        entrance.accessibilityHint = "可拖动，60 秒未点击后隐藏，可摇一摇重新打开"
        entrance.accessibilityIdentifier = "LKLogConsole.entrance"
        entrance.frame.size = CGSize(width: 72, height: 48)
        entrance.addGestureRecognizer(UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePanGestureRecognizer),
        ))
        controller.view.addSubview(entrance)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // 只拦截入口和展开内容；透明根视图不能吞掉业务页面的触摸。
        return hit === self || hit === rootViewController?.view ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // hide 会先释放根控制器，此后的布局不再调整入口。
        guard let container = rootViewController?.view else { return }
        let safe = container.bounds.inset(by: container.safeAreaInsets).insetBy(dx: 8, dy: 8)
        if !positionedEntrance, safe.width > 0, safe.height > 0 {
            entrance.center = CGPoint(x: safe.maxX - entrance.bounds.width / 2, y: safe.midY)
            positionedEntrance = true
        }
        // 旋转和分屏后仍将入口保留在可见安全区域。
        entrance.center = CGPoint(
            x: min(
                max(entrance.center.x, safe.minX + entrance.bounds.width / 2),
                safe.maxX - entrance.bounds.width / 2,
            ),
            y: min(
                max(entrance.center.y, safe.minY + entrance.bounds.height / 2),
                safe.maxY - entrance.bounds.height / 2,
            ),
        )
    }

    @objc
    private func handlePanGestureRecognizer(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: entrance.superview)
        entrance.center.x += translation.x
        entrance.center.y += translation.y
        gesture.setTranslation(.zero, in: entrance.superview)
        setNeedsLayout()
        layoutIfNeeded()
    }
}
#endif
