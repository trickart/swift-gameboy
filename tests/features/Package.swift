// swift-tools-version:5.9
// Regression test: verifies that language features (enum payloads, typed throws, existentials, generics, Int64, Float) work in a ROM.
import PackageDescription

let package = Package(
    name: "features",
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "features", dependencies: [.product(name: "GameBoy", package: "swift-gameboy")], path: "."),
    ]
)
