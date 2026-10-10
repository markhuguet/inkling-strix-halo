#!/bin/bash
# Download the pinned weights into $MODELS and verify sha256:
#   unsloth/Inkling-Small-GGUF @ GGUF_REV: UD-IQ3_XXS/* (3 shards, 97.9 GB) + mmproj-F16.gguf
#   thinkingmachines/Inkling-Small @ MTP_REV: mtp.safetensors (4.5 GB, only needed for MTP; skip with NO_MTP=1)
# Re-running resumes partial downloads and skips verified files. HF_TOKEN is passed through if set.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
inhibit_self "model download" "$@"
mkdir -p "$MODELS" "$WORK/pyenv"

verify() {  # verify every reference line whose file exists; return 1 if any listed file is missing or bad
  local missing=0 list
  list=$(grep -E "$1" "$ROOT/reference/sha256-downloads.txt")
  while read -r _ f; do [ -f "$MODELS/$f" ] || missing=1; done <<< "$list"
  [ $missing -eq 0 ] || return 1
  log "verifying sha256 ($(echo "$list" | wc -l) files)"
  (cd "$MODELS" && sha256sum -c --quiet <<< "$list")
}

fetch() {  # repo rev local_subdir patterns...
  local repo=$1 rev=$2 dir=$3; shift 3
  # plain HTTP (no Xet): partial files are kept as .incomplete and resumed on retry; the Xet client discarded ~30 GB
  # of progress on a single CDN error and buffered GBs in RAM. Retries up to 8 times.
  in_container -v "$MODELS":/models -v "$WORK/pyenv":/pyenv -e PYTHONPATH=/pyenv -e HF_TOKEN="${HF_TOKEN:-}" \
      -e HF_HUB_ENABLE_HF_TRANSFER=0 -e HF_HUB_DISABLE_XET=1 -- bash -euc '
    python3 -c "import huggingface_hub" 2>/dev/null || pip install -q --target /pyenv "huggingface_hub>=1.0,<2"
    python3 - "$@" <<PY
import sys, time
from huggingface_hub import snapshot_download
repo, rev, d, *pats = sys.argv[1:]
for attempt in range(1, 9):
    try:
        print(snapshot_download(repo_id=repo, revision=rev, local_dir="/models/" + d, allow_patterns=pats, max_workers=3))
        break
    except Exception as e:
        print(f"attempt {attempt} failed: {e!r:.300}", flush=True)
        if attempt == 8:
            raise
        time.sleep(min(60, 5 * attempt))
PY' _ "$repo" "$rev" "$dir" "$@"
}

if verify 'UD-IQ3_XXS/|mmproj'; then
  log "base GGUF already present and verified"
else
  log "downloading $GGUF_REPO@${GGUF_REV:0:9}: $BASE_QUANT + mmproj (~98 GB)"
  fetch "$GGUF_REPO" "$GGUF_REV" "" "$BASE_QUANT/*" "mmproj-F16.gguf"
  verify 'UD-IQ3_XXS/|mmproj' || die "checksum mismatch in the base GGUF"
fi

if [ "${NO_MTP:-0}" = 1 ]; then exit 0; fi
if verify 'mtp-src/'; then
  log "mtp.safetensors already present and verified"
else
  log "downloading $MTP_REPO@${MTP_REV:0:9}: mtp.safetensors (4.5 GB)"
  fetch "$MTP_REPO" "$MTP_REV" "mtp-src" "mtp.safetensors"
  verify 'mtp-src/' || die "checksum mismatch in mtp.safetensors"
fi
log "weights ready in $MODELS"
