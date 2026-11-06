// swift-tools-version:5.9
// `swift package --swift-sdk gameboy --build-system native gb-rom -c release` produces .build/plugins/GBRom/outputs/hello.gb.
// When using the public repository, replace .package(path:) with .package(url: "https://github.com/<owner>/swift-gameboy.git", ...).
import PackageDescription

let package = Package(
    name: "hello",
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "hello",
            dependencies: [.product(name: "GameBoy", package: "swift-gameboy")],
            path: "."),
    ]
)
