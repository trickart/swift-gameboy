# Building the toolchain

How to build `swift-sm83.xctoolchain`, a Swift toolchain with the SM83 (Game Boy) backend, and the Swift SDK
`gameboy` for SwiftPM. For user-facing documentation see the repository README.

Base: Swift 6.4.2 (`release/6.4.2`, LLVM 21.1). Backend ported from [llvm-z80](https://github.com/llvm-z80/llvm-z80),
tag `llvmz80-23.1.3-r1`.

| File | Role |
|---|---|
| `build.sh` | Fetch sources (`build/src`) → apply `patches/` → build-script → swift-driver → `install-toolchain.sh`. Needs macOS arm64 with Xcode 27, or Linux with a Swift 6.4 toolchain and lld or gold; takes 1.5–3 hours and about 60GB of disk |
| `install-toolchain.sh` | Installs only the required components from `build/sm83/` into `build/swift-sm83.xctoolchain`, then runs `install-gb-runtime.sh` |
| `install-gb-runtime.sh` | Replaces `usr/lib/sm83/` with the Game Boy runtime (`runtime/gb.ld` → sm83.ld, `runtime/crt0.s` → sm83_crt0.o, `runtime/runtime.c` + `runtime/compiler-rt` → sm83_rt.a). Re-run it on its own after editing `runtime/` |
| `make-swift-sdk.sh` | Generates `build/gameboy.artifactbundle` and runs `swift sdk install`. The toolset.json contains absolute paths, so re-run it after moving the toolchain |
| `export-patches.sh` | Writes the working-tree changes under `build/src/` out to `patches/*.patch` |
| `patches/` | SM83 patches for llvm-project, swift and swift-driver |
| `package-sdk.sh` | Distribution: `toolchain --host <triple>` collects and strips the files the SDK needs into `dist/toolchain-<triple>.tar.gz`; `bundle --version <v> <tarballs>` assembles them into `dist/swift-gameboy-<v>.artifactbundle.tar.gz` (one variant per host, relative paths) plus a `.sha256` for `swift sdk install --checksum` |
| `host.sh`, `sdk-json.sh` | Shared helpers: host detection (macOS / Linux build directory names) and the swift-sdk.json / toolset.json contents |

```
toolchain/build.sh                 # first build; also invoked by setup.sh
toolchain/build.sh --no-fetch      # incremental rebuild + reinstall after editing sources
toolchain/install-gb-runtime.sh    # after editing runtime/ only
toolchain/make-swift-sdk.sh        # regenerate the Swift SDK
toolchain/export-patches.sh        # export build/src changes to the patches
tools/test.sh                      # regression tests
```

On Linux the same scripts run inside the `swift:6.4.2-jammy` container (see `.github/workflows/toolchain.yml` for the
package list); build directories are named `build/sm83/{llvm,swift}-linux-<arch>` and the bundle variant additionally
contains `usr/lib/swift/linux` (the host standard library that swift-frontend loads through its rpath).

To rebuild just the compiler quickly, use `ninja -C build/sm83/swift-macosx-arm64 swift-frontend` or
`ninja -C build/sm83/llvm-macosx-arm64 clang lld`, then run `install-toolchain.sh`.

## Releases (GitHub Actions)

`.github/workflows/toolchain.yml` builds the toolchain on macOS arm64, Linux x86_64 and Linux aarch64, packages each
with `package-sdk.sh toolchain`, assembles a single bundle with `package-sdk.sh bundle`, and on a version tag (`0.1.0` style, like Swift's own tags) creates a
GitHub release with the tarball, its SHA-256 and the `swift sdk install ... --checksum ...` command. `workflow_dispatch`
runs produce the bundle as a workflow artifact only. The build uses sccache backed by the Actions cache because
GitHub-hosted runners (3-4 vCPUs, 6 hour limit) are slower than the 1.5-3 hours measured on a 10-core machine; if a
host keeps timing out, move that job to a self-hosted runner. `.github/workflows/ci.yml` checks syntax on every push
and, once a release exists, builds the samples with the latest released SDK and runs `tools/test.sh`.

A tagged release is made with `git tag 0.1.0 && git push origin 0.1.0`.

## How it works

```
main.swift ──swiftc -target sm83-none-none-elf (Embedded Swift)──▶ main.o
  ──ld.lld -T sm83.ld + sm83_crt0.o + GameBoy.o + runtime (sm83_rt.a)──▶ main.elf
  ──gb-rom plugin (segment layout + header/checksums)──▶ main.gb
```

swiftc (swift-driver) delegates linking to `clang --target=sm83-none-none-elf`, and clang invokes `ld.lld` with the
toolchain's `usr/lib/sm83/{sm83.ld,sm83_crt0.o,sm83_rt.a}` (built from `runtime/` by `install-gb-runtime.sh`).
The `gb-rom` command plugin (`Plugins/GBRom`) lays out the ELF's PT_LOAD segments at their physical addresses, fills in
the cartridge header title and checksums, and writes the `.gb` file.

SwiftPM needs `--build-system native`. The default Swift Build backend in Xcode 27 (Swift 6.4) has no linker settings
for bare-metal targets (OS `none`) and passes ld64 flags such as `-dependency_info` to ld.lld, which fails. swift-build's
`main` branch already has `BareMetalLd.xcspec`, so a future release should not need the flag. SwiftPM also loads both
Xcode's and this toolchain's libSwiftScan into one process, which produces harmless `objc[...]: Class ... is implemented
in both` and `incompatible libSwiftScan` warnings; pointing `SWIFT_DRIVER_SWIFTSCAN_LIB` at Xcode's
`lib_InternalSwiftScan.dylib` silences them (see tools/test.sh).

### Patches (`patches/`)

| Target | Contents |
|---|---|
| llvm-project | `llvm/lib/Target/Z80` (GlobalISel-based Z80/SM83 backend), `Triple::sm83`, ELF relocations, lld support for Z80 and clang's Z80 target definition, ported to LLVM 21. Also includes the Z80 compiler-rt (`sm83_rt.a`, crt0) |
| llvm-project (clang driver) | Linking for `clang --target=sm83-none-none-elf` (`ld.lld` + `usr/lib/sm83/{sm83.ld,sm83_crt0.o,sm83_rt.a}`) with support for `-L`, `-r`, and adding the `_` prefix to the `--defsym main=<module>_main` that SwiftPM passes |
| llvm-project (SM83-specific) | `swiftcc` is mapped to the SDCC `__sdcccall(0)` convention (all arguments on the stack, caller cleanup); callee cleanup does not work because Swift calls closures with mismatched argument counts. Atomics are lowered to plain instructions by the `LowerAtomic` pass (single core) |
| swift | Registers the `sm83` architecture, builds the Embedded standard library for `sm83-none-none-elf`, fixes IRGen casts that are invalid with 16-bit pointers, disables the stack protector on SM83, adds the `-data-sections` option |
| swift-driver | Adds `z80`/`sm83` to `Triple` (16-bit pointers). Built with the host Swift and bundled |

### Runtime (`runtime/`)

- `crt0.s` — vectors, cartridge header, stack setup, `.data` copy, `.bss` zeroing, OAM DMA routine, interrupt handler wrappers
- `runtime.c` — `posix_memalign`/`free`/`malloc` (first-fit allocator in WRAM), `arc4random_buf`, `ceil`/`floor` for double,
  and `gb_vram_write`/`gb_vram_fill`/`gb_vram_copy`, which write to VRAM safely while the LCD is on (wait for HBlank/VBlank
  and write immediately; doing the wait in Swift takes too long and the write is dropped, so this is written in C)
- `compiler-rt/` — double-precision arithmetic routines taken from LLVM compiler-rt
- `gb.ld` — memory map: ROM 0x0000–0x7FFF, shadow OAM 0xC000–0xC09F, `.data`/`.bss`/heap from 0xC0A0, 1KB stack (0xDC00–0xDFFF), OAM DMA routine in HRAM
