#!/bin/bash
# GPU op correctness against the CPU backend for every op the patches touch.
#   test_ops.sh OUT_DIR
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
OUT="${1:?usage: test_ops.sh OUT_DIR}"; mkdir -p "$OUT"
rc=0
for op in FLASH_ATTN_EXT_BANDED SSM_CONV MOE_ROUTE OUT_PROD MUL_MAT MUL_MAT_ID GET_ROWS; do
  in_container GPU=1 -v "$SRC":/src:ro -- /src/"$BUILD"/bin/test-backend-ops test -o "$op" -b ROCm0 \
    > "$OUT/test-ops-$op.log" 2>&1 || rc=1
  printf '  %-22s %s\n' "$op" "$(grep -E '^ *[0-9]+/[0-9]+ tests passed' "$OUT/test-ops-$op.log" | tail -1 | xargs)"
done
exit $rc
