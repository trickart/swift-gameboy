#!/bin/bash
# Build swift-sm83.xctoolchain from source.
# Hosts: macOS arm64 (Xcode 27) or Linux x86_64/aarch64 (a Swift 6.4 toolchain such as the swift:6.4.2 Docker image,
# plus cmake, ninja, python3 and the usual build dependencies; see .github/workflows/toolchain.yml).
#
#   toolchain/build.sh            # fetch -> apply patches -> build -> install into build/swift-sm83.xctoolchain
#   toolchain/build.sh --no-fetch # skip fetching and patching; rebuild only
#
# After build-script, swift-driver (the new driver) is built with the host Swift (swift build)
# and install-toolchain.sh places it in usr/bin. Required for SwiftPM (swift build --swift-sdk gameboy).
# Takes roughly 1.5-3 hours on a 10-core machine and about 60GB of disk.
# Environment variables:
#   SWIFT_GB_SRC_ROOT    where sources are checked out (default: <repo>/build/src)
#   SWIFT_GB_BUILD_ROOT  build directory (default: <repo>/build; build-script uses build/sm83/)
#   JOBS                 parallel jobs (default: number of CPUs)
#   SWIFT_USE_SCCACHE=1  let build-script use sccache (must be on PATH)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/toolchain/host.sh"
SRC="${SWIFT_GB_SRC_ROOT:-$ROOT/build/src}"
BUILD_ROOT="${SWIFT_GB_BUILD_ROOT:-$ROOT/build}"
PATCHES="$ROOT/toolchain/patches"
SWIFT_SCHEME="release/6.4.2"
JOBS="${JOBS:-$HOST_CPUS}"

fetch() {
  mkdir -p "$SRC"
  if [ ! -d "$SRC/swift" ]; then
    git clone --depth 1 -b "$SWIFT_SCHEME" https://github.com/swiftlang/swift.git "$SRC/swift"
  fi
  if [ ! -d "$SRC/llvm-project" ]; then
    # Shallow-clone only the repositories we need (llvm-project, cmark, swift-syntax, swift-driver, string-processing,
    # and swift-corelibs-libdispatch, which the Swift build compiles for the Linux host stdlib)
    local skip=()
    for r in swift-llvm-bindings llbuild swift-build swift-toolchain-sqlite swift-tools-protocols \
             swift-tools-support-core swiftpm swift-argument-parser swift-atomics swift-collections \
             swift-crypto swift-certificates swift-asn1 swift-async-algorithms swift-log swift-numerics \
             swift-system swift-stress-tester swift-testing swift-corelibs-xctest swift-corelibs-foundation \
             swift-foundation-icu swift-foundation swift-corelibs-blocksruntime \
             swift-integration-tests swift-xcode-playground-support ninja cmake indexstore-db sourcekit-lsp \
             swift-format swift-installer-scripts swift-docc swift-lmdb swift-docc-render-artifact \
             swift-docc-symbolkit swift-markdown swift-nio swift-sdk-generator wasi-libc wasmkit curl \
             libxml2 zlib brotli mimalloc swift-subprocess boringssl; do
      skip+=(--skip-repository "$r")
    done
    (cd "$SRC" && ./swift/utils/update-checkout --clone --scheme "$SWIFT_SCHEME" --skip-history "${skip[@]}") || true
  fi
  local required="llvm-project swift swift-driver"
  [ "$HOST_OS" = "Darwin" ] || required="$required swift-corelibs-libdispatch"
  for repo in $required; do
    [ -d "$SRC/$repo" ] || { echo "error: $SRC/$repo not found" >&2; exit 1; }
  done
}

apply_patches() {
  for repo in llvm-project swift swift-driver; do
    local p="$PATCHES/$repo.patch"
    [ -s "$p" ] || { echo "error: $p not found. Generate it with toolchain/export-patches.sh" >&2; exit 1; }
    (
      cd "$SRC/$repo"
      if git apply --check "$p" 2>/dev/null; then
        git apply "$p"
        echo "$repo: patch applied"
      elif git apply --check --reverse "$p" 2>/dev/null; then
        echo "$repo: patch already applied"
      else
        echo "error: cannot apply patch to $repo" >&2; exit 1
      fi
    )
  done
}

build() {
  mkdir -p "$BUILD_ROOT"
  cd "$SRC/swift"
  export SWIFT_BUILD_ROOT="$BUILD_ROOT"
  local host_args=()
  if [ "$HOST_OS" = "Darwin" ]; then
    # ARM is needed for the host compiler-rt (libclang_rt.osx.a) that libswiftCore links against
    host_args=(--llvm-targets-to-build "AArch64;ARM;X86;Z80" --swift-darwin-supported-archs arm64
               --skip-ios --skip-tvos --skip-watchos --skip-xros)
  else
    # GNU ld (bfd) cannot link Swift shared libraries ("relocation ... against protected symbol can not be used
    # when making a shared object"), and the host-side Swift libraries (swift-syntax) only honor LLVM_USE_LINKER.
    # Prefer lld (shipped with the Swift toolchain), otherwise gold (binutils).
    local linker
    if command -v ld.lld > /dev/null; then linker=lld
    elif command -v ld.gold > /dev/null; then linker=gold
    else echo "error: neither ld.lld nor ld.gold found; install lld or binutils" >&2; exit 1
    fi
    echo "Using linker: $linker"
    host_args=(--llvm-targets-to-build "AArch64;X86;Z80" --bootstrapping=hosttools
               --extra-cmake-options="-DLLVM_USE_LINKER=$linker")
  fi
  ./utils/build-script --release --assertions --no-swift-stdlib-assertions \
    --build-subdir sm83 \
    --jobs "$JOBS" \
    --skip-build-benchmarks --skip-early-swift-driver \
    --skip-build-clang-tools-extra \
    --build-lld \
    "${host_args[@]}" \
    --extra-swift-cmake-options="-DSWIFT_EMBEDDED_STDLIB_EXTRA_TARGET_TRIPLES=sm83-none-none-elf" \
    --extra-swift-cmake-options="-DSWIFT_EMBEDDED_STDLIB_BUILD_EXTRA_TARGET_TRIPLES_ONLY=ON" \
    --skip-test-swift --skip-test-cmark --skip-test-early-swift-driver --skip-test-swift-driver \
    --skip-test-swiftsyntax \
    "$@"
}

build_driver() {
  # swift-driver is a SwiftPM package, so build it with the host Swift (dependencies are fetched from GitHub)
  local scratch="$BUILD_ROOT/sm83/swift-driver-$HOST_SUFFIX"
  # --product only honors the last one, so invoke once per product
  for prod in swift-driver swift-help; do
    (cd "$SRC/swift-driver" && $HOST_SWIFT build -c release --scratch-path "$scratch" --product "$prod")
  done
}

if [ "${1:-}" != "--no-fetch" ]; then
  fetch
  apply_patches
else
  shift
fi
build "$@"
build_driver
SWIFT_GB_BUILD_ROOT="$BUILD_ROOT" "$ROOT/toolchain/install-toolchain.sh"
