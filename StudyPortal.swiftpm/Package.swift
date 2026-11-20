// swift-tools-version: 5.9

// Swift Playgrounds（iPad）でそのまま開ける App プロジェクト
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Study Portal",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Study Portal",
            targets: ["AppModule"],
            bundleIdentifier: "app.studyportal.timer",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .clock),
            accentColor: .presetColor(.yellow),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
