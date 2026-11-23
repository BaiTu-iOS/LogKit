# LogKit

[English](README.md) | 简体中文

LogKit 为 iOS 和 macOS 上的 Swift 与 Objective-C 提供按分类记录日志的接口。Swift 的 `@Logger` 宏可以为类型创建日志通道。只有输出端或观察者接收当前级别时，日志消息才会在调用线程上求值。

## 安装

在 Xcode 或 Swift Package Manager 中添加 `https://github.com/BaiTu-iOS/LogKit.git`，选择 `LogKit` 产品。支持 iOS 15 和 macOS 12 起的系统。1.0 版的源码宏依赖 SwiftSyntax 604.0.0。

## Swift

```swift
import LogKit

@Logger("Network")
final class Connection {
    func didConnect() {
        log.info("连接成功")
    }
}
```

分类名必须是无插值的字符串字面量。普通类、结构体和 actor 会获得实例和静态 `log`，枚举只获得静态 `log`。泛型上下文以及 extension 中的嵌套类型会跳过静态属性。类型已有名为 `log` 的成员时，编译器会报错。也可以直接创建通道，例如 `let log = LogChannel("Network")`。

## 输出与订阅

默认通过 Apple 统一日志系统输出 Info、Warning、Error 和 Fatal 级别的日志。要写入文件或切换输出方式，可将实现 `LKLogDestination` 的对象赋给 `LKLogCenter.shared().destination`。输出端的方法可能被多个线程同时调用。

```swift
let observation = LKLogCenter.shared().observe(minimumLevel: .debug) { entry in
    // 在记录日志的线程上读取 entry.category 和 entry.message。
}
// 在需要接收日志期间持有 observation。
observation.cancel()
```

订阅的最低级别独立于输出端。取消或释放订阅后停止接收日志。日志正文应避免包含凭据和个人信息。

## 可选的 Debug 日志中控（iOS）

需要应用内日志界面时，额外选择 `LogKitConsole` 产品。它只依赖 `LogCore`，不会由 `LogKit` 自动引入。所有 Console 源码（包括导入、订阅和 SQLite 历史存储）均在 `#if DEBUG && canImport(UIKit)` 内；Release 不提供 Console 类型，也不采集历史。不要在 Release 配置中定义 `DEBUG`。产品仍可留在依赖图中。

```swift
#if DEBUG && canImport(UIKit)
import LogKitConsole
#endif

// 主线程调用；presenter 必须已进入宿主窗口。
#if DEBUG && canImport(UIKit)
LKLogConsole.shared.install()
LKLogConsole.shared.show(from: presenter)
#endif
```

支持实时日志、等级/模块/时间筛选、全文搜索、JSON 详情以及单条原文复制与分享。安装后保留最多 5,000 条、正文载荷最多 10 MiB 的本地缓存历史；隐藏或折叠只关闭页面，`uninstall()` 才停止订阅和历史采集，已有缓存不会删除。需要摇一摇入口时，Debug 下使用 `LKLogConsoleShakeWindow` 作为宿主窗口。

本模块迁移自 BTLoggerConsole，使用独立的 `LogKitConsole` 缓存目录和偏好键，不读取旧组件的历史。当前不提供 xlog ZIP 分享，因为 LogKit 尚无文件打包接口。Console 暂时保持原组件的 Swift 5 语言模式。

## Objective-C

```objc
@import LogCore;

LK_LOG_INFO("Network", @"已连接到 %@", serverName);
```

在 macOS 上运行 `swift test` 可验证日志运行时和宏展开。

## 预编译宏（Apple Silicon Mac）

使用 Xcode 27.2 (27B52) 的团队可以从 [1.0.0 发布页](https://github.com/BaiTu-iOS/LogKit/releases/tag/1.0.0) 下载预编译包，按发布页的 SHA-256 校验后，解压到工程的 `Vendor/LogKit`。在 Xcode 中将该目录作为本地 Swift Package 添加，选择 `LogKit` 产品。在每个使用 `@Logger` 的 target 的 **Other Swift Flags** 加入：

```text
$(inherited) -Xfrontend -load-plugin-executable -Xfrontend "$(SRCROOT)/Vendor/LogKit/Plugins/LogCompilerPlugin#LogCompilerPlugin"
```

包内包含相同版本的日志运行时源码，编译时直接执行随包提供的 macOS arm64 插件，无需下载或编译 SwiftSyntax。插件只在构建 Mac 上运行。普通 Git 地址安装仍走源码宏，两种方式选一种即可。升级 Xcode 时应重新验证插件兼容性。

## Mars 文件日志引擎

自 1.1.0 起，在 iOS 工程中添加 `LogKit` 产品会一并链接 Mars xlog，无需单独添加依赖。macOS 使用原有日志运行时。

SwiftPM 下载锁定的 XCFramework ZIP 并校验 SHA-256。[mars-source 分支](https://github.com/BaiTu-iOS/LogKit/tree/mars-source) 保存 xlog 定制补丁、许可证和重建脚本。
