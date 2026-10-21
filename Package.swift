// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pasteroo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pasteroo",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Pasteroo",
            // build-app.sh puts Sparkle.framework in Contents/Frameworks; `swift run` finds it next to the binary.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                           "-Xlinker", "-rpath", "-Xlinker", "@loader_path"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
