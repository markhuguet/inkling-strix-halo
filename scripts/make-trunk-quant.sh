#!/bin/bash
# Build $MODELS/$BASE_QUANT-trunk-$TRUNK_TYPE from the downloaded GGUF: requantize only its Q6_K trunk tensors
# (attention q/o/k/v, shared experts, dense FFN) to TRUNK_TYPE using an importance matrix computed from the downloaded
# model itself; every other tensor is copied byte-identical. Steps (each skipped when its output exists):
#   1. calibration text: wikitext-2 train (first 260 KB) + llama.cpp sources from the pinned tree
#   2. imatrix: 160 x 512 tokens on the GPU (~12 min). Run with the op-by-op MoE routing (LLAMA_INKLING_NO_MOE_ROUTE=1),
#      which is bit-identical to the build the pinned checksums were made with; the fused routing differs in the last bits
#   3. llama-quantize with a per-tensor type file (tools/gen_types.py) (~1 min, writes ~91 GB)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ "$TRUNK_TYPE" != none ] || { log "TRUNK_TYPE=none: nothing to do"; exit 0; }
DST="$BASE_QUANT-trunk-$TRUNK_TYPE"
Q="$WORK/trunk-quant"; mkdir -p "$Q"
REF="$ROOT/reference/sha256-$DST.txt"
if [ -f "$REF" ] && (cd "$MODELS" && sha256sum -c --quiet "$REF" 2>/dev/null); then log "$DST already built and verified"; exit 0; fi
for b in llama-imatrix llama-quantize; do
  [ -x "$SRC/$BUILD/bin/$b" ] || die "missing $b (TARGETS=\"llama-imatrix llama-quantize\" scripts/build-llama.sh)"
done

if [ ! -f "$Q/calib.txt" ]; then
  log "calibration text"
  [ -f "$Q/wikitext.zip" ] || curl -fsSL -o "$Q/wikitext.zip" "$WIKITEXT_URL"
  echo "$WIKITEXT_SHA256  $Q/wikitext.zip" | sha256sum -c --quiet
  ( set +o pipefail   # head closes its pipes early on purpose
    unzip -p "$Q/wikitext.zip" wikitext-2-raw/wiki.train.raw | head -c 260000
    head -c 70000 "$SRC/src/llama-context.cpp"
    (cd "$SRC/gguf-py/gguf" && LC_ALL=C ls *.py | head -6 | xargs cat) | head -c 50000 ) > "$Q/calib.txt.tmp"
  mv "$Q/calib.txt.tmp" "$Q/calib.txt"
fi

BASE_SHARD="$(first_shard "$BASE_QUANT")"
if [ ! -f "$Q/imatrix.gguf" ]; then
  log "imatrix (160 chunks x 512 tokens, GPU)"
  INHIBIT_WHY=imatrix inhibit podman run --rm --security-opt label=disable --device /dev/kfd --device /dev/dri \
      --group-add keep-groups --ipc=host --ulimit memlock=-1:-1 -v "$MODELS":/models:ro -v "$SRC":/src:ro -v "$Q":/q \
      -e LLAMA_INKLING_NO_MOE_ROUTE=1 \
      "$IMAGE" /src/"$BUILD"/bin/llama-imatrix -m "/models/$BASE_SHARD" -f /q/calib.txt -o /q/imatrix.gguf.tmp \
      -c 512 --chunks 160 -ngl 999 -fa on -lm none > "$Q/imatrix.log" 2>&1 || { tail -20 "$Q/imatrix.log"; die "imatrix failed"; }
  mv "$Q/imatrix.gguf.tmp" "$Q/imatrix.gguf"
fi

log "type file: pin all tensors, trunk Q6_K -> $TRUNK_TYPE"
in_container -v "$ROOT/tools":/tools:ro -v "$SRC":/src:ro -v "$MODELS":/models:ro -v "$Q":/q -e PYTHONPATH=/src/gguf-py -- \
  python3 /tools/gen_types.py "/models/$BASE_QUANT" "/q/types-$TRUNK_TYPE.txt" "$TRUNK_TYPE"

log "llama-quantize -> $DST"
mkdir -p "$MODELS/$DST"
in_container -v "$MODELS":/models -v "$SRC":/src:ro -v "$Q":/q -- \
  /src/"$BUILD"/bin/llama-quantize --allow-requantize --imatrix /q/imatrix.gguf --tensor-type-file "/q/types-$TRUNK_TYPE.txt" \
  --keep-split "/models/$BASE_SHARD" "/models/$DST/Inkling-Small-$DST.gguf" Q4_K_M "$JOBS" > "$Q/quantize-$TRUNK_TYPE.log" 2>&1 \
  || { tail -20 "$Q/quantize-$TRUNK_TYPE.log"; die "quantize failed"; }
grep -E 'model size|quant size' "$Q/quantize-$TRUNK_TYPE.log" | sed 's/^/  /'
if [ -f "$REF" ]; then log "verifying sha256"; (cd "$MODELS" && sha256sum -c "$REF"); else log "no reference checksums at $REF"; fi
