#!/bin/bash
# Assemble swift-sm83.xctoolchain from the built Swift + LLVM (Z80/SM83).
# Usage: install-toolchain.sh [destination .xctoolchain]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/toolchain/host.sh"
BUILD=${SWIFT_GB_BUILD_ROOT:-$ROOT/build}/sm83
DEST=${1:-$ROOT/build/swift-sm83.xctoolchain}
PREFIX=$DEST/usr

rm -rf "$DEST"
mkdir -p "$PREFIX"

# LLVM / clang / lld: install only the tools we need
for c in clang clang-resource-headers lld llvm-mc llvm-objcopy llvm-nm llvm-ar llvm-objdump \
         llvm-readobj llvm-size llvm-strip llvm-readelf Z80Runtime; do
  cmake --install "$BUILD/llvm-$HOST_SUFFIX" --component "$c" --prefix "$PREFIX" > /dev/null \
    || echo "warning: failed to install LLVM component $c"
done

# Swift: compiler and standard library (including Embedded sm83)
for c in compiler compiler-swift-syntax-lib swift-syntax-lib clang-builtin-headers autolink-driver \
         libexec stdlib license; do
  cmake --install "$BUILD/swift-$HOST_SUFFIX" --component "$c" --prefix "$PREFIX" > /dev/null \
    || echo "warning: failed to install Swift component $c"
done

# Linux: libdispatch (libdispatch.so, libBlocksRuntime.so, Dispatch module) that the host stdlib links against
if [ "$HOST_OS" != "Darwin" ]; then
  cmake --install "$BUILD/libdispatch-$HOST_SUFFIX" --prefix "$PREFIX" > /dev/null \
    || echo "warning: failed to install libdispatch (build.sh passes --libdispatch on Linux)"
fi

# swift-driver (new driver): swiftc/swift pick it up automatically when swift-driver sits in the same directory.
# Required for SwiftPM's swift build --swift-sdk. Without it, the legacy (C++) driver is used.
DRIVER_BUILD=$BUILD/swift-driver-$HOST_SUFFIX/release
if [ -x "$DRIVER_BUILD/swift-driver" ]; then
  cp "$DRIVER_BUILD/swift-driver" "$PREFIX/bin/"
  [ -x "$DRIVER_BUILD/swift-help" ] && cp "$DRIVER_BUILD/swift-help" "$PREFIX/bin/"
else
  echo "warning: $DRIVER_BUILD/swift-driver not found (run build_driver in build.sh)"
fi

# Replace usr/lib/sm83 with the Game Boy runtime (runtime/{gb.ld,crt0.s,runtime.c,compiler-rt})
"$ROOT/toolchain/install-gb-runtime.sh" "$DEST"

cat > "$DEST/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Aliases</key><array><string>swift-sm83</string></array>
  <key>CFBundleIdentifier</key><string>org.swift-gameboy.sm83</string>
  <key>CompatibilityVersion</key><integer>2</integer>
  <key>CompatibilityVersionDisplayString</key><string>Xcode 27.0</string>
  <key>DisplayName</key><string>Swift for Game Boy (SM83)</string>
  <key>ReportProblemURL</key><string>https://github.com/llvm-z80/llvm-z80</string>
  <key>ShortDisplayName</key><string>Swift SM83</string>
  <key>Version</key><string>6.4.2</string>
</dict>
</plist>
EOF

echo "Installed: $DEST"
ls "$PREFIX/bin" | tr '\n' ' '; echo
ls "$PREFIX/lib/swift/embedded/Swift.swiftmodule" 2>/dev/null || echo "warning: Embedded standard library not found"
ls "$PREFIX/lib/sm83" 2>/dev/null || echo "warning: usr/lib/sm83 (sm83_rt.a) not found"
du -sh "$DEST"
