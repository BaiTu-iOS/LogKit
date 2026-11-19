// swift-tools-version: 6.0
// Created by yuxilong on 2026/10/22.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "LogKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "LogKit", targets: ["LogKit", "LogCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        .binaryTarget(name: "mars", path: "Vendor/Mars/mars.xcframework.zip"),
        .macro(
            name: "LogCompilerPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
        ),
        .target(name: "LogCore"),
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
