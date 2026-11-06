#!/bin/bash
# Build swift-sm83.xctoolchain from source (requires macOS arm64 / Xcode 27 / a Swift 6.4 toolchain).
#
#   toolchain/build.sh            # fetch -> apply patches -> build -> install into build/swift-sm83.xctoolchain
#   toolchain/build.sh --no-fetch # skip fetching and patching; rebuild only
#
# After build-script, swift-driver (the new driver) is built with the host Swift (xcrun swift build)
# and install-toolchain.sh places it in usr/bin. Required for SwiftPM (swift build --swift-sdk gameboy).
# Takes roughly 1.5-3 hours and about 60GB of disk.
# Environment variables:
#   SWIFT_GB_SRC_ROOT    where sources are checked out (default: <repo>/build/src)
#   SWIFT_GB_BUILD_ROOT  build directory (default: <repo>/build; build-script uses build/sm83/)
#   JOBS                 parallel jobs (default: number of CPUs)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SWIFT_GB_SRC_ROOT:-$ROOT/build/src}"
BUILD_ROOT="${SWIFT_GB_BUILD_ROOT:-$ROOT/build}"
PATCHES="$ROOT/toolchain/patches"
SWIFT_SCHEME="release/6.4.2"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

fetch() {
  mkdir -p "$SRC"
  if [ ! -d "$SRC/swift" ]; then
    git clone --depth 1 -b "$SWIFT_SCHEME" https://github.com/swiftlang/swift.git "$SRC/swift"
  fi
  if [ ! -d "$SRC/llvm-project" ]; then
    # Shallow-clone only the repositories we need (llvm-project, cmark, swift-syntax, swift-driver, string-processing)
    local skip=()
    for r in swift-llvm-bindings llbuild swift-build swift-toolchain-sqlite swift-tools-protocols \
             swift-tools-support-core swiftpm swift-argument-parser swift-atomics swift-collections \
             swift-crypto swift-certificates swift-asn1 swift-async-algorithms swift-log swift-numerics \
             swift-system swift-stress-tester swift-testing swift-corelibs-xctest swift-corelibs-foundation \
             swift-foundation-icu swift-foundation swift-corelibs-libdispatch swift-corelibs-blocksruntime \
             swift-integration-tests swift-xcode-playground-support ninja cmake indexstore-db sourcekit-lsp \
             swift-format swift-installer-scripts swift-docc swift-lmdb swift-docc-render-artifact \
             swift-docc-symbolkit swift-markdown swift-nio swift-sdk-generator wasi-libc wasmkit curl \
             libxml2 zlib brotli mimalloc swift-subprocess boringssl; do
      skip+=(--skip-repository "$r")
    done
    (cd "$SRC" && ./swift/utils/update-checkout --clone --scheme "$SWIFT_SCHEME" --skip-history "${skip[@]}") || true
  fi
  for repo in llvm-project swift swift-driver; do
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
  ./utils/build-script --release --assertions --no-swift-stdlib-assertions \
    --build-subdir sm83 \
    --jobs "$JOBS" \
    --skip-build-benchmarks --skip-early-swift-driver \
    --skip-ios --skip-tvos --skip-watchos --skip-xros \
    --skip-build-clang-tools-extra \
    --build-lld \
    --llvm-targets-to-build "AArch64;ARM;X86;Z80" \
    --swift-darwin-supported-archs arm64 \
    --extra-swift-cmake-options="-DSWIFT_EMBEDDED_STDLIB_EXTRA_TARGET_TRIPLES=sm83-none-none-elf" \
    --extra-swift-cmake-options="-DSWIFT_EMBEDDED_STDLIB_BUILD_EXTRA_TARGET_TRIPLES_ONLY=ON" \
    --skip-test-swift --skip-test-cmark --skip-test-early-swift-driver --skip-test-swift-driver \
    --skip-test-swiftsyntax \
    "$@"
}

build_driver() {
  # swift-driver is a SwiftPM package, so build it with the host Swift (dependencies are fetched from GitHub)
  local scratch="$BUILD_ROOT/sm83/swift-driver-macosx-arm64"
  # --product only honors the last one, so invoke once per product
  for prod in swift-driver swift-help; do
    (cd "$SRC/swift-driver" && xcrun swift build -c release --scratch-path "$scratch" --product "$prod")
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
