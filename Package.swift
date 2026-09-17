// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tardy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tardy", targets: ["Tardy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        // Pure logic (alert states, scheduling, formatting, link parsing): no AppKit, fully tested
        .target(name: "TardyCore"),
        .executableTarget(
            name: "Tardy",
            dependencies: ["TardyCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "TardyCoreTests", dependencies: ["TardyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
