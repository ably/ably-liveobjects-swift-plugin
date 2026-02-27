// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AblyLiveObjects",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .tvOS(.v14),
    ],
    products: [
        .library(
            name: "AblyLiveObjects",
            targets: [
                "AblyLiveObjects",
            ],
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ably/ably-cocoa.git",
            revision: "932846e0be7657f3571f4671261b8ccac1ceb818",
        ),
        .package(
            url: "https://github.com/ably/ably-cocoa-plugin-support.git",
            revision: "242fac1d4a829c8a63f9b3f96a71809e1f6eeffc",
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0",
        ),
        .package(
            url: "https://github.com/apple/swift-async-algorithms",
            from: "1.0.1",
        ),
        .package(
            url: "https://github.com/JanGorman/Table.git",
            from: "1.1.1",
        ),
        .package(
            url: "https://github.com/apple/swift-docc-plugin",
            from: "1.0.0",
        ),
    ],
    targets: [
        .target(
            name: "AblyLiveObjects",
            dependencies: [
                .product(
                    name: "Ably",
                    package: "ably-cocoa",
                ),
                .product(
                    name: "_AblyPluginSupportPrivate",
                    package: "ably-cocoa-plugin-support",
                ),
            ],
        ),
        .testTarget(
            name: "AblyLiveObjectsTests",
            dependencies: [
                "AblyLiveObjects",
                .product(
                    name: "Ably",
                    package: "ably-cocoa",
                ),
                .product(
                    name: "_AblyPluginSupportPrivate",
                    package: "ably-cocoa-plugin-support",
                ),
            ],
            resources: [
                .copy("ably-common"),
            ],
        ),
        .executableTarget(
            name: "BuildTool",
            dependencies: [
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser",
                ),
                .product(
                    name: "AsyncAlgorithms",
                    package: "swift-async-algorithms",
                ),
                .product(
                    name: "Table",
                    package: "Table",
                ),
            ],
        ),
    ],
)
