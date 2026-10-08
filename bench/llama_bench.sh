#!/bin/bash
# Raw engine throughput with llama-bench (no server): decode tg64 at depth 0 / 1K / 16K, prefill pp512 at 0 / 8K.
#   llama_bench.sh OUT_DIR      (needs the GPU free: stop the server first)
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
OUT="${1:?usage: llama_bench.sh OUT_DIR}"; mkdir -p "$OUT"
SHARD="$(first_shard "$QUANT")"
run() {  # name, llama-bench args...
  local name=$1; shift
  log "llama-bench $name"
  inhibit podman run --rm --security-opt label=disable --device /dev/kfd --device /dev/dri --group-add keep-groups \
      --ipc=host -v "$MODELS":/models:ro -v "$SRC":/src:ro "$IMAGE" \
      /src/"$BUILD"/bin/llama-bench -m "/models/$SHARD" -ngl 999 -fa 1 -lm none -r "${REPS:-3}" -o jsonl "$@" \
      > "$OUT/llama-bench-$name.jsonl" 2> "$OUT/llama-bench-$name.log"
  python3 - "$OUT/llama-bench-$name.jsonl" <<'P'
import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l)
    kind = f"pp{d['n_prompt']}" if d["n_prompt"] else f"tg{d['n_gen']}"
    print(f"  {kind} @ depth {d['n_depth']:>5}: {d['avg_ts']:7.2f} ± {d['stddev_ts']:.2f} tok/s")
P
}
run decode  -p 0   -n 64 -d 0,1024,16384
run prefill -p 512 -n 0  -d 0,8192
