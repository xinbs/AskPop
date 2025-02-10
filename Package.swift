// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AskPop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AskPop", targets: ["AskPop"])
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.1"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.2")
    ],
    targets: [
        .executableTarget(
            name: "AskPop",
            dependencies: [
                "KeychainAccess",
                "SwiftyJSON",
                "Highlightr"
            ],
            path: "src",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-framework", "AppKit"])
            ]
        )
    ]
) 