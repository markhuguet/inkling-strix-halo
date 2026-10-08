# Shared settings for every script. Override any of these in the environment.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"

WORK="${WORK:-$ROOT/work}"                              # llama.cpp checkout + build live here
SRC="${SRC:-$WORK/llama.cpp}"
BUILD="${BUILD:-build}"                                 # build dir inside $SRC
MODELS="${MODELS:-$HOME/models/Inkling-Small-GGUF}"     # ~100 GB per quant; put it on a fast local disk
RESULTS="${RESULTS:-$ROOT/results}"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# podman run in the dev image; GPU=1 adds the ROCm devices. Extra podman args go before "--".
#   in_container [GPU=1] [podman args...] -- cmd...
in_container() {
  local gpu=() pargs=()
  if [ "${1:-}" = "GPU=1" ]; then
    gpu=(--device /dev/kfd --device /dev/dri --group-add keep-groups --ipc=host --ulimit memlock=-1:-1)
    shift
  fi
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do pargs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  podman run --rm --security-opt label=disable "${gpu[@]}" "${pargs[@]}" "$IMAGE" "$@"
}

# keep the machine awake for long runs (a laptop suspend mid-benchmark silently ruins numbers)
inhibit() {
  if command -v systemd-inhibit >/dev/null; then
    systemd-inhibit --what=sleep:idle --who=inkling-strix-halo --why="${INHIBIT_WHY:-benchmark}" "$@"
  else
    "$@"
  fi
}

first_shard() {  # $1 = quant dir name
  local f
  f="$(cd "$MODELS" && ls "$1"/*00001-of-*.gguf 2>/dev/null | head -1)"
  [ -n "$f" ] || die "no GGUF shards in $MODELS/$1 (run scripts/download-model.sh / make-mtp-gguf.sh)"
  echo "$f"
}
