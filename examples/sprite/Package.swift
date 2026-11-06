// swift-tools-version:5.9
// `swift package --swift-sdk gameboy --build-system native gb-rom -c release` produces .build/plugins/GBRom/outputs/sprite.gb.
// When using the public repository, replace .package(path:) with .package(url: "https://github.com/<owner>/swift-gameboy.git", ...).
import PackageDescription

let package = Package(
    name: "sprite",
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "sprite",
            dependencies: [.product(name: "GameBoy", package: "swift-gameboy")],
            path: "."),
    ]
)
