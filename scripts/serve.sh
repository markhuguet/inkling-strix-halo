#!/bin/bash
# Serve Inkling-Small with the patched llama-server on 127.0.0.1:$PORT (OpenAI-compatible API + web UI).
#
#   PROFILE=default  UD-IQ3_XXS, n-gram speculative drafting (best for copy-heavy edits, no extra weights)
#   PROFILE=mtp      UD-IQ3_XXS-MTP, n-gram first then the model's own MTP head (1 draft token) as fallback
#
# Env: PORT (8732) CTX (196608) SLOTS (1) KV_TYPE (f16) SPEC_TYPE TEMPLATE_KWARGS EXTRA_ENV ("-e K=V ...").
# Extra arguments are passed to llama-server. Runs in the foreground; Ctrl-C (or scripts/stop.sh) stops it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROFILE="${PROFILE:-default}"
case "$PROFILE" in
  default) Q="$QUANT";     SPEC="${SPEC_TYPE:-ngram-simple}";           PARGS=() ;;
  mtp)     Q="$QUANT-MTP"; SPEC="${SPEC_TYPE:-ngram-simple,draft-mtp}"; PARGS=(--spec-draft-n-max 1) ;;
  *) die "unknown PROFILE '$PROFILE' (default|mtp)" ;;
esac
PORT="${PORT:-8732}"
CTX="${CTX:-196608}"   # KV positions. Only 7 global layers keep full context: ~30 KiB/token, ~100 GiB GTT in total at 196K
SLOTS="${SLOTS:-1}"
# >1 slot must share one KV stream: per-slot streams disable the banded attention kernels (dense fallback, 40 GB
# compute buffer, ~1.5 tok/s)
UNIFIED=(); [ "$SLOTS" -gt 1 ] && UNIFIED=(--kv-unified)
SHARD="$(first_shard "$Q")"
[ -x "$SRC/$BUILD/bin/llama-server" ] || die "no llama-server in $SRC/$BUILD (scripts/build-llama.sh)"

podman rm -f inkling-server >/dev/null 2>&1 || true
log "profile $PROFILE: $SHARD, spec $SPEC, ctx $CTX, slots $SLOTS -> http://127.0.0.1:$PORT"
# shellcheck disable=SC2086
INHIBIT_WHY="inkling server" inhibit podman run --rm --name inkling-server ${EXTRA_ENV:-} \
  --security-opt label=disable \
  --device /dev/kfd --device /dev/dri --group-add keep-groups \
  --ipc=host --ulimit memlock=-1:-1 \
  -v "$MODELS":/models:ro -v "$SRC":/src:ro \
  -p 127.0.0.1:"$PORT":8080 \
  "$IMAGE" \
  /src/"$BUILD"/bin/llama-server \
    -m "/models/$SHARD" \
    --mmproj /models/mmproj-F16.gguf \
    --alias "inkling-small-${Q,,}" \
    --host 0.0.0.0 --port 8080 \
    -ngl 999 -fa on --load-mode none \
    -ctk "${KV_TYPE:-f16}" -ctv "${KV_TYPE:-f16}" \
    -c "$CTX" -np "$SLOTS" "${UNIFIED[@]}" \
    --jinja --temp 1.0 --top-p 1.0 \
    --chat-template-kwargs "${TEMPLATE_KWARGS:-{\"reasoning_effort\":\"none\"}}" \
    --spec-type "$SPEC" "${PARGS[@]}" \
    --metrics "$@"
