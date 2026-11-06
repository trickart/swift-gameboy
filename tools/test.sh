#!/bin/bash
# Regression tests: build the examples and test packages with swift package gb-rom, then verify their serial output in the bundled emulator.
# Requirements: the Swift SDK "gameboy" (toolchain/make-swift-sdk.sh) and the host SwiftPM (Xcode 27 / Swift 6.4).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMU="$ROOT/tools/sm83emu.py"
fail=0

swift sdk list 2>/dev/null | grep -qx gameboy || { echo "error: Swift SDK gameboy is not installed (toolchain/make-swift-sdk.sh)" >&2; exit 1; }
# Suppress the warnings SwiftPM emits when it loads libSwiftScan from both Xcode and our toolchain (objc[...] / incompatible libSwiftScan)
export SWIFT_DRIVER_SWIFTSCAN_LIB="$(xcrun --find swiftc | xargs dirname)/../lib/swift/host/lib_InternalSwiftScan.dylib"

build() {  # build <package directory> -> prints the ROM path
  local dir=$1 name; name=$(basename "$dir")
  (cd "$dir" && swift package --swift-sdk gameboy --build-system native gb-rom -c release 2>&1 \
     | grep -v "^warning: '--build-system\|^objc\[" | grep "ROM\|error" || true)
}

check() {  # check <name> <ROM> <frames> <expected substring of serial output> [--press SPEC]
  local name=$1 rom=$2 frames=$3 expect=$4; shift 4
  local out
  out=$(python3 -I "$EMU" "$rom" --frames "$frames" "$@" 2>&1 || true)
  if echo "$out" | grep -q "status=OK\|status=FINISHED" && [[ "$out" == *"$expect"* ]] && ! echo "$out" | grep -q "^warning: LCD"; then
    echo "  OK   $name"
  else
    echo "  FAIL $name"; echo "$out" | head -20; fail=1
  fi
}

echo "== examples/hello"
build "$ROOT/examples/hello"
check hello "$ROOT/examples/hello/.build/plugins/GBRom/outputs/hello.gb" 130 "Sum sq even: 220"

echo "== examples/sprite"
build "$ROOT/examples/sprite"
check sprite "$ROOT/examples/sprite/.build/plugins/GBRom/outputs/sprite.gb" 100 "beeps: 2" --press "10:RIGHT,40:A,42:,50:A,52:"

echo "== tests/features (language features)"
build "$ROOT/tests/features"
check features "$ROOT/tests/features/.build/plugins/GBRom/outputs/features.gb" 90 $'24\n42\n200\n6\n9\n1\n1099511627776\n15'

if [ $fail -eq 0 ]; then echo "All tests passed"; else echo "Some tests failed"; exit 1; fi
