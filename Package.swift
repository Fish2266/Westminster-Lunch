// swift-tools-version: 5.9
import PackageDescription

// A test-only package. It does NOT build the app: it wraps the `Shared/`
// sources — the exact files the watch app and the widget compile — as a plain
// library so they can be unit tested with `swift test` on the Mac, with no
// watchOS simulator or device involved. `WestminsterLunch.xcodeproj` is still
// the only way to build and run the app itself, and it ignores this file.
let package = Package(
    name: "WestminsterLunch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WestminsterLunchCore", path: "Shared"),
        .testTarget(
            name: "WestminsterLunchCoreTests",
            dependencies: ["WestminsterLunchCore"],
            path: "Tests/WestminsterLunchCoreTests"
        ),
    ]
)
