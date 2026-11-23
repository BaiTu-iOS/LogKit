// Created by yuxilong on 2026/09/16.

#if DEBUG && canImport(UIKit)
import UIKit

/// 可选的宿主窗口基类：使用系统摇一摇事件打开已启用的中控，不启动传感器轮询。
/// 宿主在主线程创建窗口并调用 LKLogConsole.shared.install()；也可继承此类。
@objc(LKLogConsoleShakeWindow)
open class LKLogConsoleShakeWindow: UIWindow {
    /// 允许窗口接收系统运动事件，不主动抢占文本输入焦点。
    override open var canBecomeFirstResponder: Bool {
        true
    }

    /// 只消费已成功打开中控的摇一摇；其余事件继续沿系统响应链传递。
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake, let rootViewController,
           LKLogConsole.shared.show(from: rootViewController) { return }
        super.motionEnded(motion, with: event)
    }
}
#endif
