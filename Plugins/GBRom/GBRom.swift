// swift package gb-rom: a SwiftPM command plugin.
// Builds the executable products (with the Swift SDK gameboy) and converts the resulting ELF into a Game Boy ROM (.gb).
// Performs the equivalent of llvm-objcopy -O binary plus cartridge header fix-up (title, checksums, 32KB padding) in pure Swift, without external tools.
//
// Usage (from the package directory):
//   swift package --swift-sdk gameboy --build-system native [-c release] gb-rom [--product NAME] [-c release|debug]
//                                                                           [--output PATH] [--title TITLE] [--verbose]
// The build configuration is taken from the -c after gb-rom, or else from swift package's -c (default debug).
// The default output is .build/plugins/GBRom/outputs/<product>.gb (a location the sandbox allows writing to).
// To write elsewhere inside the package with --output, pass --allow-writing-to-package-directory to swift package.
import Foundation
import PackagePlugin

let romSize = 0x8000  // 32KB (no MBC)
let wramStart: UInt32 = 0xC000, wramEnd: UInt32 = 0xE000
let hramStart: UInt32 = 0xFF80, hramEnd: UInt32 = 0xFFFF

struct GBRomError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

@main
struct GBRom: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Normalize short options to their long form (ArgumentExtractor only handles --name style)
        let short = ["-c": "--configuration", "-o": "--output", "-v": "--verbose", "-h": "--help"]
        var ex = ArgumentExtractor(arguments.map { short[$0] ?? $0 })
        if ex.extractFlag(named: "help") > 0 {
            print(usage)
            return
        }
        let products = ex.extractOption(named: "product")
        let configuration = ex.extractOption(named: "configuration").last ?? "inherit"
        let output = ex.extractOption(named: "output").last
        let title = ex.extractOption(named: "title").last
        let verbose = ex.extractFlag(named: "verbose") > 0
        guard ex.remainingArguments.isEmpty else {
            throw GBRomError("Unknown argument(s): \(ex.remainingArguments.joined(separator: " "))\n\(usage)")
        }
        guard let config = PackageManager.BuildConfiguration(rawValue: configuration), config != .inherit || configuration == "inherit" else {
            throw GBRomError("-c must be debug or release: \(configuration)")
        }

        // Target executable products. If none are given, all executable products of the root package.
        let executables = context.package.products.compactMap { $0 as? ExecutableProduct }
        let targets: [ExecutableProduct]
        if products.isEmpty {
            targets = executables
        } else {
            targets = try products.map { name in
                guard let p = executables.first(where: { $0.name == name }) else {
                    throw GBRomError("No executable product named '\(name)' (available: \(executables.map(\.name).joined(separator: ", ")))")
                }
                return p
            }
        }
        guard !targets.isEmpty else {
            throw GBRomError("Package '\(context.package.displayName)' has no executable products")
        }
        if output != nil && targets.count > 1 {
            throw GBRomError("--output can only be used with a single product (select one with --product)")
        }

        for product in targets {
            // 1. Build (the --swift-sdk / --build-system passed to the calling swift package are used as-is)
            var params = PackageManager.BuildParameters(configuration: config, logging: verbose ? .verbose : .concise)
            params.echoLogs = verbose
            let result = try packageManager.build(.product(product.name), parameters: params)
            guard result.succeeded else {
                if !verbose { print(result.logText) }
                throw GBRomError("Build of '\(product.name)' failed")
            }
            guard let artifact = result.builtArtifacts.first(where: { $0.kind == .executable }) else {
                throw GBRomError("Executable for '\(product.name)' not found in the build result")
            }
            let elf = URL(fileURLWithPath: artifact.path.string)

            // 2. ELF -> ROM
            let image = try ROMImage(elf: Data(contentsOf: elf))
            let romTitle = title ?? product.name
            let rom = image.finalizedROM(title: romTitle)

            // 3. Write out
            let outURL: URL
            if let output {
                outURL = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            } else {
                outURL = URL(fileURLWithPath: context.pluginWorkDirectory.string).appendingPathComponent("\(product.name).gb")
            }
            do {
                try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try rom.write(to: outURL)
            } catch {
                throw GBRomError("""
                    Cannot write \(outURL.path): \(error.localizedDescription)
                    By default the plugin can only write to .build/plugins/GBRom/outputs/. To write elsewhere inside the package, run
                    `swift package --allow-writing-to-package-directory ... gb-rom --output ...`.
                    """)
            }
            let config = elf.deletingLastPathComponent().lastPathComponent  // release / debug
            print("[\(product.name)] Done: \(relativePath(outURL, from: context.package.directory.string)) (\(config), title: \(ROMImage.headerTitle(romTitle)))")
            print("  ROM : \(pad(image.romUsed)) / \(romSize) bytes (\(image.romUsed * 100 / romSize)%)")
            print("  WRAM: \(pad(image.wramUsed)) bytes (static)  HRAM \(image.hramUsed) bytes")
        }
    }

}

/// ROM image built by laying out the ELF PT_LOAD segments at their physical addresses (positions in ROM). Yields the same result as llvm-objcopy -O binary.
struct ROMImage {
    var bytes: [UInt8]       // raw image from the start of ROM (gaps are 0)
    var romUsed: Int         // ROM bytes in use (equivalent to __rom_used)
    var wramUsed: Int        // .data + .bss (statically allocated WRAM)
    var hramUsed: Int

    init(elf d: Data) throws {
        func u16(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
        func u32(_ o: Int) -> UInt32 { UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24 }
        guard d.count >= 0x34, d[0] == 0x7F, d[1] == 0x45, d[2] == 0x4C, d[3] == 0x46 else {
            throw GBRomError("Not an ELF file")
        }
        guard d[4] == 1, d[5] == 1 else { throw GBRomError("A 32-bit little-endian ELF is required") }
        let phoff = Int(u32(0x1C)), phentsize = u16(0x2A), phnum = u16(0x2C)
        guard phentsize >= 32, d.count >= phoff + phentsize * phnum else { throw GBRomError("ELF program headers are corrupt") }

        var image = [UInt8]()
        var romUsed = 0, wram = 0, hram = 0
        for i in 0..<phnum {
            let p = phoff + i * phentsize
            guard u32(p) == 1 else { continue }  // PT_LOAD
            let offset = Int(u32(p + 4)), vaddr = u32(p + 8), paddr = Int(u32(p + 12))
            let filesz = Int(u32(p + 16)), memsz = Int(u32(p + 20))
            if vaddr >= wramStart && vaddr < wramEnd { wram += memsz }
            if vaddr >= hramStart && vaddr < hramEnd { hram += memsz }
            guard filesz > 0 else { continue }
            guard paddr + filesz <= romSize else {
                throw GBRomError("ROM exceeds 32KB (0x\(String(paddr + filesz, radix: 16)) bytes). MBC is not supported")
            }
            guard offset + filesz <= d.count else { throw GBRomError("ELF segment points outside the file") }
            if image.count < paddr + filesz { image.append(contentsOf: repeatElement(0, count: paddr + filesz - image.count)) }
            image.replaceSubrange(paddr..<(paddr + filesz), with: d[offset..<(offset + filesz)])
            romUsed = max(romUsed, paddr + filesz)
        }
        guard romUsed >= 0x150 else { throw GBRomError("ROM has no cartridge header (0x100-0x14F). Is crt0 linked in?") }
        bytes = image
        self.romUsed = romUsed
        wramUsed = wram
        hramUsed = hram
    }

    /// Header title string (uppercase ASCII, up to 15 characters, unusable characters become _).
    static func headerTitle(_ title: String) -> String {
        let s = title.uppercased().unicodeScalars.map { c -> Character in
            (c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c))) ? Character(c) : "_"
        }
        return String(s.prefix(15))
    }

    /// Same fix-up as gbfix.py: pad to 32KB with 0xFF, set title, ROM size, and header/global checksums.
    func finalizedROM(title: String) -> Data {
        var rom = bytes + [UInt8](repeating: 0xFF, count: romSize - bytes.count)
        let t = Array(ROMImage.headerTitle(title).utf8)
        rom.replaceSubrange(0x134..<0x143, with: t + [UInt8](repeating: 0, count: 15 - t.count))
        rom[0x148] = 0x00
        var x: UInt8 = 0
        for i in 0x134..<0x14D { x = x &- rom[i] &- 1 }
        rom[0x14D] = x
        rom[0x14E] = 0; rom[0x14F] = 0
        var g: UInt16 = 0
        for b in rom { g = g &+ UInt16(b) }
        rom[0x14E] = UInt8(g >> 8)
        rom[0x14F] = UInt8(g & 0xFF)
        return Data(rom)
    }
}

func pad(_ n: Int) -> String { String(repeating: " ", count: max(0, 6 - String(n).count)) + String(n) }

func relativePath(_ url: URL, from base: String) -> String {
    let p = url.standardizedFileURL.path
    let b = base.hasSuffix("/") ? base : base + "/"
    return p.hasPrefix(b) ? String(p.dropFirst(b.count)) : p
}

let usage = """
    Usage: swift package --swift-sdk gameboy --build-system native gb-rom [options]
      -c, --configuration <config>  release / debug (default: follows swift package's -c, else debug)
      --product <name>              Executable product to convert (default: all executable products of the root package)
      -o, --output <path>           Output path (default: .build/plugins/GBRom/outputs/<product>.gb). Writing elsewhere
                                    inside the package requires --allow-writing-to-package-directory on swift package
      --title <string>              Cartridge header title (default: product name; uppercase, up to 15 characters)
      -v, --verbose                 Show the build log
    """
