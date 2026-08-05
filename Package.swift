// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MeetingRecorderCore",
            path: "Sources/MeetingRecorderCore"
        ),
        .executableTarget(
            name: "MeetingRecorder",
            dependencies: ["MeetingRecorderCore"],
            path: "Sources/MeetingRecorder"
        ),
        .testTarget(
            name: "MeetingRecorderCoreTests",
            dependencies: ["MeetingRecorderCore"],
            path: "Tests/MeetingRecorderCoreTests"
        )
    ]
)
