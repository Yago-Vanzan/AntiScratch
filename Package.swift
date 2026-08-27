// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntiScratchCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AntiScratchCore",
            path: "AntiScratch",
            exclude: [
                "AntiScratchApp.swift",
                "Assets.xcassets",
                "Info.plist",
                "Note.swift",
                "ScratchpadView.swift"
            ],
            sources: ["InlineCalculator.swift"]
        ),
        .testTarget(
            name: "AntiScratchCoreTests",
            dependencies: ["AntiScratchCore"],
            path: "AntiScratchTests"
        )
    ]
)
