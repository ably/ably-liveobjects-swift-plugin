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
            url: "https://github.com/ably/ably-cocoa",
            // TODO: Unpin before next release
            revision: "8dde3e841aa1f861176c1341cf44e92014b95857",
        ),
        .package(
            url: "https://github.com/ably/ably-cocoa-plugin-support",
            // TODO: Unpin before next release
            revision: "2ce1058ed4430cc3563dcead0299e92a81d2774b",
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
