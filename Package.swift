// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AerisWriter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
    ],
    targets: [
        // Pure logic: Markdown parsing/rendering. No AppKit, so it's unit-testable.
        .target(
            name: "MarkdownCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        // Pure logic: library folder listing and tree. Foundation only, no AppKit.
        .target(name: "LibraryCore"),
        // The AppKit application.
        .executableTarget(
            name: "AerisWriter",
            dependencies: ["MarkdownCore", "LibraryCore"]
        ),
        // CLT-runnable smoke check (XCTest needs full Xcode). `swift run mdcheck`.
        .executableTarget(
            name: "mdcheck",
            dependencies: ["MarkdownCore", "LibraryCore"]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"]
        ),
        .testTarget(
            name: "LibraryCoreTests",
            dependencies: ["LibraryCore"]
        ),
    ]
)
