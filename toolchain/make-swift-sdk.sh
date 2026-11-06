#!/bin/bash
# Generate the Swift SDK "gameboy" for SwiftPM and `swift sdk install` it.
#
#   toolchain/make-swift-sdk.sh            # create build/gameboy.artifactbundle and install it (replacing any existing one)
#   toolchain/make-swift-sdk.sh --no-install
#
# The generated toolset.json contains absolute paths into the toolchain, so re-run this after moving the toolchain.
# Usage: swift package --swift-sdk gameboy --build-system native gb-rom -c release
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="${SWIFT_GB_TOOLCHAIN:-$ROOT/build/swift-sm83.xctoolchain}"
NAME=gameboy
TRIPLE=sm83-none-none-elf
BUNDLE="$ROOT/build/$NAME.artifactbundle"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :Version' "$TC/Info.plist" 2>/dev/null || echo 0.0.1)

[ -x "$TC/usr/bin/swiftc" ] || { echo "error: $TC/usr/bin/swiftc not found" >&2; exit 1; }
[ -x "$TC/usr/bin/swift-driver" ] || { echo "error: $TC/usr/bin/swift-driver not found (SwiftPM requires the new driver)" >&2; exit 1; }
[ -f "$TC/usr/lib/swift/embedded/Swift.swiftmodule/$TRIPLE.swiftmodule" ] || { echo "error: Embedded standard library for $TRIPLE not found" >&2; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/$NAME"
cat > "$BUNDLE/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "$NAME": {
      "type": "swiftSDK",
      "version": "$VERSION",
      "variants": [ { "path": "$NAME/swift-sdk.json" } ]
    }
  }
}
JSON
# Without swiftResourcesPath, SwiftPM passes the SDK directory itself as -resource-dir and the
# Embedded standard library is not found. Point it at the toolchain's usr/lib/swift explicitly.
cat > "$BUNDLE/$NAME/swift-sdk.json" <<JSON
{
  "schemaVersion": "4.0",
  "targetTriples": {
    "$TRIPLE": {
      "swiftResourcesPath": "$TC/usr/lib/swift",
      "swiftStaticResourcesPath": "$TC/usr/lib/swift_static",
      "toolsetPaths": [ "toolset.json" ]
    }
  }
}
JSON
# swiftCompiler extraCLIOptions are added to both the compile and the link invocations of swiftc.
# -Osize comes after the -O/-Onone that SwiftPM adds, so it takes precedence (keeps debug builds within ROM).
cat > "$BUNDLE/$NAME/toolset.json" <<JSON
{
  "schemaVersion": "1.0",
  "rootPath": "$TC/usr/bin",
  "swiftCompiler": {
    "extraCLIOptions": [
      "-enable-experimental-feature", "Embedded",
      "-enable-experimental-feature", "Extern",
      "-wmo",
      "-Osize",
      "-Xfrontend", "-disable-stack-protector",
      "-Xfrontend", "-disable-objc-interop",
      "-Xfrontend", "-function-sections",
      "-Xfrontend", "-data-sections",
      "-Xlinker", "--gc-sections"
    ]
  },
  "cCompiler": {
    "extraCLIOptions": [ "-Os", "-ffreestanding", "-fno-builtin", "-ffunction-sections", "-fdata-sections" ]
  }
}
JSON
echo "Generated: $BUNDLE"
if [ "${1:-}" != "--no-install" ]; then
  if swift sdk list 2>/dev/null | grep -qx "$NAME"; then
    swift sdk remove "$NAME" >/dev/null
  fi
  swift sdk install "$BUNDLE"
  echo "Installed Swift SDKs:"; swift sdk list
fi
