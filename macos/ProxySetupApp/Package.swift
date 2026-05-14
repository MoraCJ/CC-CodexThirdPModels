// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProxySetupApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ProxySetupApp", targets: ["ProxySetupApp"])
    ],
    targets: [
        .executableTarget(
            name: "ProxySetupApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ProxySetupAppTests",
            dependencies: ["ProxySetupApp"],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        )
    ]
)
