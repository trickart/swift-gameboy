#!/bin/bash
# Shared helper: writes the swift-sdk.json and toolset.json of one Swift SDK variant.
# Sourced by make-swift-sdk.sh (development SDK, absolute paths) and package-sdk.sh (distributable bundle, relative paths).
#
#   write_sdk_json <variant dir> <toolchain usr dir as seen from the variant dir>
#
# The swiftCompiler extraCLIOptions are passed to every swiftc invocation (compile and link).
# -Osize comes after the -O/-Onone that SwiftPM adds, so it takes precedence (debug builds still fit in ROM).
# swiftResourcesPath must be set explicitly; otherwise SwiftPM passes the SDK directory itself as -resource-dir
# and the Embedded standard library is not found.
write_sdk_json() {
  local dir=$1 usr=$2
  cat > "$dir/swift-sdk.json" <<JSON
{
  "schemaVersion": "4.0",
  "targetTriples": {
    "sm83-none-none-elf": {
      "swiftResourcesPath": "$usr/lib/swift",
      "swiftStaticResourcesPath": "$usr/lib/swift",
      "toolsetPaths": [ "toolset.json" ]
    }
  }
}
JSON
  cat > "$dir/toolset.json" <<JSON
{
  "schemaVersion": "1.0",
  "rootPath": "$usr/bin",
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
}
