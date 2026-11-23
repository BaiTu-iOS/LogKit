// swift-tools-version: 6.0
// Created by yuxilong on 2026/10/22.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "LogKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "LogKit", targets: ["LogKit", "LogCore"]),
        .library(name: "LogKitConsole", targets: ["LogKitConsole"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "mars",
            url: "https://raw.githubusercontent.com/BaiTu-iOS/LogKit/df8abc2930112586bd09d917bb4027da76d4536a/Vendor/Mars/mars.xcframework.zip",
            checksum: "f700a4ffb24c51d1a490aa054d3929e764353d057a6283d53f6d8bf0ef02a67b",
        ),
        .macro(
            name: "LogCompilerPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
        ),
        .target(name: "LogCore"),
        .target(
            name: "LogKitConsole",
            dependencies: ["LogCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3", .when(platforms: [.iOS], configuration: .debug))],
        ),
        .target(
            name: "LogKit",
            dependencies: [
                "LogCompilerPlugin",
                "LogCore",
                .target(name: "mars", condition: .when(platforms: [.iOS])),
            ],
            linkerSettings: [
                .linkedFramework("CoreTelephony", .when(platforms: [.iOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.iOS])),
                .linkedLibrary("c++", .when(platforms: [.iOS])),
                .linkedLibrary("resolv.9", .when(platforms: [.iOS])),
                .linkedLibrary("z", .when(platforms: [.iOS])),
            ],
        ),
        .testTarget(name: "LogObservationTests", dependencies: ["LogCore"]),
        .testTarget(name: "LogChannelTests", dependencies: ["LogKit"]),
        .testTarget(
            name: "LogMacroTests",
            dependencies: [
                "LogCompilerPlugin",
                "LogKit",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
        ),
    ],
)
