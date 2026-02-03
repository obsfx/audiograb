// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "audiograb",
    platforms: [
        .macOS("14.2")
    ],
    targets: [
        .executableTarget(
            name: "audiograb",
            path: "Sources",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Info.plist",
                ])
            ]
        )
    ]
)
