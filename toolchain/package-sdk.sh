#!/bin/bash
# Build a distributable, self-contained Swift SDK bundle.
#
#   toolchain/package-sdk.sh toolchain --host <triple> [--toolchain <path>] [--out <dir>]
#       Collects the files the SDK needs from an installed swift-sm83.xctoolchain (compiler, driver, clang, lld,
#       Embedded standard library, Game Boy runtime, ...), strips them, and writes <out>/toolchain-<triple>.tar.gz.
#       <triple> is the host the toolchain runs on, e.g. arm64-apple-macosx or x86_64-unknown-linux-gnu.
#
#   toolchain/package-sdk.sh bundle --version <version> [--out <dir>] toolchain-<triple>.tar.gz...
#       Assembles the per-host tarballs into <out>/swift-gameboy-<version>.artifactbundle.tar.gz with one SDK variant
#       per host (selected by SwiftPM through supportedTriples), plus a .sha256 file for `swift sdk install --checksum`.
#
# Everything in the bundle is referenced with relative paths, so it can be installed from any location:
#   swift sdk install https://github.com/<owner>/swift-gameboy/releases/download/<tag>/swift-gameboy-<version>.artifactbundle.tar.gz \
#                     --checksum <sha256>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/toolchain/sdk-json.sh"

die() { echo "error: $*" >&2; exit 1; }
WORK=""
trap '[ -n "$WORK" ] && rm -rf "$WORK"' EXIT

# Files to ship, relative to the toolchain's usr/. Missing entries are skipped (not every host has them).
BIN_FILES="swift-frontend swiftc swift swift-driver swift-help swift-autolink-extract clang-21 clang clang++ lld ld.lld llvm-ar llvm-objcopy llvm-nm llvm-size"
LIB_DIRS="lib/swift/host lib/swift/embedded lib/swift/shims lib/swift/clang/include lib/swift/clang/share lib/swift/linux lib/sm83"
LIB_FILES="lib/swift/module.modulemap lib/swift/apinotes"

strip_binary() {  # strip_binary <file> (skips symlinks and non-binaries)
  local f=$1
  [ -L "$f" ] && return 0
  case "$(uname -s)" in
    Darwin) strip -x "$f" 2>/dev/null || true ;;
    *)      strip --strip-unneeded "$f" 2>/dev/null || true ;;
  esac
}

cmd_toolchain() {
  local host="" tc="$ROOT/build/swift-sm83.xctoolchain" out="$ROOT/dist"
  while [ $# -gt 0 ]; do
    case "$1" in
      --host) host=$2; shift 2 ;;
      --toolchain) tc=$2; shift 2 ;;
      --out) out=$2; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "$host" ] || die "--host <triple> is required"
  [ -x "$tc/usr/bin/swift-frontend" ] || die "$tc is not a built toolchain"
  [ -x "$tc/usr/bin/swift-driver" ] || die "$tc has no swift-driver (SwiftPM needs the new driver)"
  [ -f "$tc/usr/lib/sm83/sm83_rt.a" ] || die "$tc has no Game Boy runtime (run install-gb-runtime.sh)"

  local work; work=$(mktemp -d); WORK=$work   # cleaned up by the EXIT trap below
  local usr="$work/toolchain/usr"
  mkdir -p "$usr/bin" "$usr/lib"

  for f in $BIN_FILES; do
    [ -e "$tc/usr/bin/$f" ] && cp -a "$tc/usr/bin/$f" "$usr/bin/"
  done
  for d in $LIB_DIRS; do
    [ -d "$tc/usr/$d" ] || continue
    mkdir -p "$usr/$(dirname "$d")"
    cp -a "$tc/usr/$d" "$usr/$d"
  done
  for f in $LIB_FILES; do
    [ -e "$tc/usr/$f" ] && cp -a "$tc/usr/$f" "$usr/$f"
  done
  # clang resource directory (stdint.h etc. for the C runtime); only the headers are needed
  for inc in "$tc"/usr/lib/clang/*/include; do
    [ -d "$inc" ] || continue
    local rel=${inc#"$tc/usr/"}
    mkdir -p "$usr/$(dirname "$rel")"
    cp -a "$inc" "$usr/$rel"
  done
  rm -rf "$usr/lib/swift/host/plugins"   # macro plugins are not used for Embedded targets

  # Linux: the executables find their shared libraries via rpath ($ORIGIN/../lib/swift/linux etc.), so everything
  # they need must be inside the package. Fail early if something is missing instead of shipping a broken bundle.
  if [ "$(uname -s)" = "Linux" ] && command -v ldd > /dev/null; then
    local missing=""
    for f in swift-frontend swift-driver clang-21 lld; do
      [ -e "$usr/bin/$f" ] || continue
      missing="$missing$(ldd "$usr/bin/$f" 2>/dev/null | grep 'not found' | sed "s|^|  $f:|")"
    done
    [ -z "$missing" ] || die "shared libraries missing from the package:
$missing"
  fi
  cp "$tc/Info.plist" "$work/toolchain/" 2>/dev/null || true

  # Strip executables and shared libraries (roughly halves the size). Ad-hoc signatures on macOS stay valid.
  for f in "$usr"/bin/*; do strip_binary "$f"; done
  find "$usr/lib" \( -name '*.dylib' -o -name '*.so' -o -name '*.so.*' \) -type f | while read -r f; do strip_binary "$f"; done

  mkdir -p "$out"; out=$(cd "$out" && pwd)   # tar runs from another directory, so make it absolute
  local tarball="$out/toolchain-$host.tar.gz"
  (cd "$work" && tar czf "$tarball" toolchain)
  echo "Packaged: $tarball ($(du -h "$tarball" | cut -f1), unpacked $(du -sh "$work/toolchain" | cut -f1))"
}

cmd_bundle() {
  local version="" out="$ROOT/dist" tarballs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) version=$2; shift 2 ;;
      --out) out=$2; shift 2 ;;
      *) tarballs+=("$1"); shift ;;
    esac
  done
  [ -n "$version" ] || die "--version <version> is required"
  [ ${#tarballs[@]} -gt 0 ] || die "no toolchain-<triple>.tar.gz given"

  local name="swift-gameboy-$version.artifactbundle"
  local work; work=$(mktemp -d); WORK=$work   # cleaned up by the EXIT trap below
  local bundle="$work/$name"
  mkdir -p "$bundle/gameboy"

  local variants=""
  for t in "${tarballs[@]}"; do
    local base; base=$(basename "$t")
    local host=${base#toolchain-}; host=${host%.tar.gz}
    [ "$host" != "$base" ] || die "$t is not named toolchain-<triple>.tar.gz"
    local vdir="$bundle/gameboy/$host"
    mkdir -p "$vdir"
    tar xzf "$(cd "$(dirname "$t")" && pwd)/$(basename "$t")" -C "$vdir"
    [ -x "$vdir/toolchain/usr/bin/swift-frontend" ] || die "$t does not contain toolchain/usr/bin/swift-frontend"
    write_sdk_json "$vdir" "toolchain/usr"
    [ -z "$variants" ] || variants="$variants,"
    variants="$variants
      { \"path\": \"gameboy/$host/swift-sdk.json\", \"supportedTriples\": [\"$host\"] }"
    echo "Variant: $host"
  done
  cat > "$bundle/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "gameboy": {
      "type": "swiftSDK",
      "version": "$version",
      "variants": [$variants
      ]
    }
  }
}
JSON

  mkdir -p "$out"; out=$(cd "$out" && pwd)
  local tarball="$out/$name.tar.gz"
  (cd "$work" && tar czf "$tarball" "$name")
  local sum
  if command -v sha256sum >/dev/null; then sum=$(sha256sum "$tarball" | cut -d' ' -f1); else sum=$(shasum -a 256 "$tarball" | cut -d' ' -f1); fi
  echo "$sum" > "$tarball.sha256"
  echo "Bundle: $tarball ($(du -h "$tarball" | cut -f1))"
  echo "SHA256: $sum"
}

case "${1:-}" in
  toolchain) shift; cmd_toolchain "$@" ;;
  bundle) shift; cmd_bundle "$@" ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
