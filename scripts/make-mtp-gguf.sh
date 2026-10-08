#!/bin/bash
# Build $MODELS/$QUANT-MTP: the 3 shards of $QUANT (reflink copies where the filesystem allows, so ~0 extra space)
# plus a 4th shard holding the 8 MTP depth layers in Q8_0 (tools/convert_mtp.py). Deterministic: the result is
# checked against reference/sha256-$QUANT-MTP.txt.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
SRCQ="$QUANT"; DSTQ="$QUANT-MTP"
[ -f "$MODELS/mtp-src/mtp.safetensors" ] || die "missing $MODELS/mtp-src/mtp.safetensors (scripts/download-model.sh)"
[ -d "$SRC/gguf-py" ] || die "no llama.cpp checkout at $SRC (scripts/fetch-llama.sh): gguf-py comes from it"

REF="$ROOT/reference/sha256-$DSTQ.txt"
if [ -f "$REF" ] && (cd "$MODELS" && sha256sum -c --quiet "$REF" 2>/dev/null); then
  log "$DSTQ already built and verified"; exit 0
fi

mkdir -p "$MODELS/$DSTQ"
for n in 2 3; do
  log "copying shard $n (reflink if supported)"
  cp --reflink=auto "$MODELS/$SRCQ/Inkling-Small-$SRCQ-0000$n-of-00003.gguf" \
                    "$MODELS/$DSTQ/Inkling-Small-$DSTQ-0000$n-of-00004.gguf"
done
log "writing shard 1 (metadata) and shard 4 (MTP tensors)"
in_container -v "$ROOT/tools":/tools:ro -v "$SRC":/src:ro -v "$MODELS":/models -e PYTHONPATH=/src/gguf-py -- \
  python3 /tools/convert_mtp.py /models/$SRCQ Inkling-Small-$SRCQ /models/mtp-src/mtp.safetensors /models/$DSTQ Inkling-Small-$DSTQ
if [ -f "$REF" ]; then
  log "verifying sha256"
  (cd "$MODELS" && sha256sum -c "$REF")
else
  log "no reference checksums for $DSTQ ($REF); not verified"
fi
