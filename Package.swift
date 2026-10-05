// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The linker needs an absolute path for the helper's embedded Info.plist.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Tardy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tardy", targets: ["Tardy"]),
        .executable(name: "tardy-events", targets: ["TardyEvents"]),
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
        // Today's meetings as JSON, for the Claude Code mod in claude-code/; shipped in Contents/Helpers
        .executableTarget(
            name: "TardyEvents",
            dependencies: ["TardyCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", "\(root)/Resources/TardyEvents-Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "TardyCoreTests", dependencies: ["TardyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
