// swift-tools-version:5.9
// swift-gameboy: a Swift library for the Game Boy (GameBoy) and a ROM-building plugin (GBRom).
// Use it together with the Swift SDK "gameboy" (sm83-none-none-elf). The Embedded Swift flags
// (-enable-experimental-feature Embedded, -wmo, -Osize, ...) come from the SDK's toolset.json, so they are not set here.
//
// GBRom is the `swift package gb-rom` command plugin. It can be used from executable packages that depend
// on this package, and converts the built ELF into a Game Boy ROM (.gb) (Plugins/GBRom/GBRom.swift).
import PackageDescription

let package = Package(
    name: "swift-gameboy",
    products: [
        .library(name: "GameBoy", targets: ["GameBoy"]),
        .plugin(name: "GBRom", targets: ["GBRom"]),
    ],
    targets: [
        .target(name: "GameBoy"),
        .plugin(
            name: "GBRom",
            capability: .command(
                intent: .custom(verb: "gb-rom", description: "Build executable products and convert them into Game Boy ROMs (.gb)"),
                permissions: [])),
    ]
)
