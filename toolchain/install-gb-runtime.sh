#!/bin/bash
# Replace the toolchain's usr/lib/sm83/ with the Game Boy runtime.
#   sm83.ld      <- runtime/gb.ld      (ROM/WRAM/HRAM memory map, cartridge header region)
#   sm83_crt0.o  <- runtime/crt0.s     (vectors, header, stack setup, .data copy, interrupt wrappers)
#   sm83_rt.a    += runtime/runtime.c, runtime/compiler-rt/*.c (allocator, double arithmetic)
# With this, the link step of `swiftc -target sm83-none-none-elf ... -o game.elf` (clang -> ld.lld)
# produces a Game Boy ELF as is. Called from install-toolchain.sh, but can also be run standalone.
# Usage: install-gb-runtime.sh [path to .xctoolchain]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=${1:-${SWIFT_GB_TOOLCHAIN:-$ROOT/build/swift-sm83.xctoolchain}}
BIN=$DEST/usr/bin
LIBDIR=$DEST/usr/lib/sm83
[ -x "$BIN/clang" ] && [ -x "$BIN/llvm-mc" ] && [ -x "$BIN/llvm-ar" ] || { echo "error: tools not found in $BIN" >&2; exit 1; }
[ -f "$LIBDIR/sm83_rt.a" ] || { echo "error: $LIBDIR/sm83_rt.a not found (Z80Runtime component)" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/runtime/gb.ld" "$LIBDIR/sm83.ld"
"$BIN/llvm-mc" -triple=sm83 -filetype=obj "$ROOT/runtime/crt0.s" -o "$LIBDIR/sm83_crt0.o"

objs=()
for src in "$ROOT/runtime/runtime.c" "$ROOT"/runtime/compiler-rt/*.c; do
  obj="$TMP/gb_$(basename "${src%.c}").o"
  "$BIN/clang" --target=sm83 -Os -ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
    -c "$src" -o "$obj"
  objs+=("$obj")
done
# Existing members with the same name are replaced (re-running does not grow the archive)
"$BIN/llvm-ar" rcs "$LIBDIR/sm83_rt.a" "${objs[@]}"
echo "Game Boy runtime installed: $LIBDIR (sm83.ld, sm83_crt0.o, ${#objs[@]} objects added to sm83_rt.a)"
