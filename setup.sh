#!/bin/bash
# swift-gameboy setup: prepares a Swift toolchain with the SM83 (Game Boy) backend.
#
#   ./setup.sh            # build build/swift-sm83.xctoolchain from source if missing, then register the Swift SDK "gameboy"
#   ./setup.sh --check    # check only
#
# Environment variables:
#   SWIFT_GB_TOOLCHAIN    path to an existing swift-sm83.xctoolchain (use it instead of building)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/build/swift-sm83.xctoolchain"
STDLIB="usr/lib/swift/embedded/Swift.swiftmodule/sm83-none-none-elf.swiftmodule"

have_toolchain() { [ -x "$1/usr/bin/swiftc" ] && [ -f "$1/$STDLIB" ] && [ -f "$1/usr/lib/sm83/sm83_rt.a" ]; }

if [ -n "${SWIFT_GB_TOOLCHAIN:-}" ]; then
  if have_toolchain "$SWIFT_GB_TOOLCHAIN"; then
    echo "Using SWIFT_GB_TOOLCHAIN=$SWIFT_GB_TOOLCHAIN"
  else
    echo "error: $SWIFT_GB_TOOLCHAIN is not a Swift toolchain with sm83-none-none-elf support" >&2; exit 1
  fi
elif have_toolchain "$DEST"; then
  echo "Toolchain already present at $DEST"
elif [ "${1:-}" = "--check" ]; then
  echo "error: $DEST not found. Run ./setup.sh to build it" >&2; exit 1
else
  echo "Building the SM83-enabled Swift toolchain from source (requires Xcode 27 and Swift 6.4; takes 1.5-3 hours)"
  "$ROOT/toolchain/build.sh"
fi

# Swift SDK "gameboy" for SwiftPM (swift package --swift-sdk gameboy). Requires a toolchain that bundles swift-driver
TC="${SWIFT_GB_TOOLCHAIN:-$DEST}"
if [ -x "$TC/usr/bin/swift-driver" ]; then
  if [ "${1:-}" = "--check" ] && swift sdk list 2>/dev/null | grep -qx gameboy; then
    echo "Swift SDK gameboy is already installed"
  else
    echo; SWIFT_GB_TOOLCHAIN="$TC" "$ROOT/toolchain/make-swift-sdk.sh"
  fi
else
  echo "note: $TC has no swift-driver, so the Swift SDK (needed for swift build) will not be created"
fi
echo
echo "Ready. Example:"
echo "  cd examples/hello && swift package --swift-sdk gameboy --build-system native gb-rom -c release"
echo "  python3 ../../tools/sm83emu.py .build/plugins/GBRom/outputs/hello.gb --ascii"
