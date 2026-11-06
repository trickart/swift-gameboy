#!/bin/bash
# Export the patches needed for SM83 support from the working trees under build/src/ into toolchain/patches/.
# (The llvm-project patch also contains new files such as llvm/lib/Target/Z80.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SWIFT_GB_SRC_ROOT:-$ROOT/build/src}"
OUT="$ROOT/toolchain/patches"
mkdir -p "$OUT"
for repo in llvm-project swift swift-driver; do
  (
    cd "$SRC/$repo"
    git add -A -N . >/dev/null   # include new files in the diff (intent-to-add)
    git diff --binary HEAD -- . ':!*.rej' ':!*.orig' > "$OUT/$repo.patch"
    git reset -q >/dev/null 2>&1 || true
    echo "$repo: $(wc -l < "$OUT/$repo.patch") lines -> $OUT/$repo.patch"
  )
done
