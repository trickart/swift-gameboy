#!/bin/bash
# Shared helper: host-specific values for the toolchain build scripts. Sourced, not executed.
#   HOST_OS      Darwin or Linux
#   HOST_SUFFIX  build-script's build directory suffix: macosx-arm64, linux-x86_64, linux-aarch64
#   HOST_TRIPLE  the Swift SDK's supportedTriples entry for this host
#   HOST_CPUS    number of CPUs
#   HOST_SWIFT   command to run the host Swift toolchain ("xcrun swift" on macOS, "swift" elsewhere)
HOST_OS=$(uname -s)
case "$HOST_OS" in
  Darwin)
    HOST_SUFFIX="macosx-$(uname -m)"
    HOST_TRIPLE="$(uname -m)-apple-macosx"
    HOST_CPUS=$(sysctl -n hw.ncpu)
    HOST_SWIFT="xcrun swift"
    ;;
  Linux)
    HOST_SUFFIX="linux-$(uname -m)"
    HOST_TRIPLE="$(uname -m)-unknown-linux-gnu"
    HOST_CPUS=$(nproc)
    HOST_SWIFT="swift"
    ;;
  *) echo "error: unsupported host OS: $HOST_OS" >&2; exit 1 ;;
esac
