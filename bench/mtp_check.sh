#!/bin/bash
# Teacher-forced MTP head accuracy: how often MTP depth d's argmax equals the target model's own greedy token.
#   mtp_check.sh OUT_DIR     (needs the GPU free and $QUANT-MTP built)
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
OUT="${1:?usage: mtp_check.sh OUT_DIR}"; mkdir -p "$OUT"
SHARD="$(first_shard "$QUANT-MTP")"
inhibit podman run --rm --security-opt label=disable --device /dev/kfd --device /dev/dri --group-add keep-groups \
    --ipc=host -v "$MODELS":/models:ro -v "$SRC":/src:ro -v "$ROOT/bench/data":/data:ro "$IMAGE" \
    /src/"$BUILD"/bin/llama-mtp-check -m "/models/$SHARD" -f /data/mtp_text.txt -n 1024 --depths 3 \
    > "$OUT/mtp-check.txt" 2> "$OUT/mtp-check.log"
sed 's/^/  /' "$OUT/mtp-check.txt"
