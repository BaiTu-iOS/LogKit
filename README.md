# LogKit

[简体中文](README.zh-CN.md) | English

LogKit provides category-based logging for Swift and Objective-C on iOS and macOS. A Swift member macro creates a log channel bound to the category you choose. Messages are evaluated on the calling thread only when a destination or observer accepts the level.

## Install

Add `https://github.com/BaiTu-iOS/LogKit.git` to your Xcode project or Swift package and select the `LogKit` product. Version 1.0 uses SwiftSyntax 604.0.0.

## Swift

```swift
import LogKit

@Logger("Network")
final class Connection {
    func didConnect() {
        log.info("Connected")
    }
}
```

The macro accepts a string literal. Concrete classes, structs and actors get instance and static channels. Enums get only a static channel. Generic contexts omit static storage. A member already named `log` produces a compiler diagnostic. To use a channel directly, write `let log = LogChannel("Network")`.

## Output and observation

By default, Info, Warning, Error and Fatal entries go to Apple unified logging. Install an object conforming to `LKLogDestination` on `LKLogCenter.shared().destination` to supply a file writer or another destination. Destination methods may run concurrently.

```swift
let observation = LKLogCenter.shared().observe(minimumLevel: .debug) { entry in
    // Consume entry.category and entry.message on the logging thread.
}
observation.cancel()
```

Keep the observation alive while collecting events. Its threshold is independent of the output destination. Releasing the observation stops delivery. Avoid logging credentials and personal data.

## Objective-C

```objc
@import LogCore;

LK_LOG_INFO("Network", @"Connected to %@", serverName);
```

Run `swift test` on macOS to verify the runtime and macro expansion.

## Prebuilt macro for Apple Silicon Macs

The [1.0.0 release](https://github.com/BaiTu-iOS/LogKit/releases/tag/1.0.0) provides a local Swift package for Xcode 27.2 (27B52). Check the archive against the published SHA-256 and extract it to `Vendor/LogKit`. Add that directory as a local package and select the `LogKit` product. In each target that uses `@Logger`, add this to **Other Swift Flags**:

```text
$(inherited) -Xfrontend -load-plugin-executable -Xfrontend "$(SRCROOT)/Vendor/LogKit/Plugins/LogCompilerPlugin#LogCompilerPlugin"
```

This package includes the runtime sources and a host-side arm64 executable, so consumers can build without SwiftSyntax. Installing the regular Git package builds the macro from source. Recheck compiler compatibility when upgrading Xcode.

## Mars file logging engine

Starting with 1.1.0, the LogKit product links Mars xlog on iOS. macOS uses the existing logging runtime.

The binary target downloads the pinned XCFramework ZIP and verifies its SHA-256. The [mars-source branch](https://github.com/BaiTu-iOS/LogKit/tree/mars-source) contains the xlog patches, licenses and rebuild script.
