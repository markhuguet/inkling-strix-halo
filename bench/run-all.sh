#!/bin/bash
# Full reproduction run: op tests, llama-bench, MTP head accuracy, then the server suite for each profile.
# Writes results/<date>-<host>/ and a summary.md comparing against reference/reference-results.json.
#   bench/run-all.sh      ~45 min; needs the GPU to itself
# Env: PROFILES ("default mtp"), STEPS ("ops bench mtp server": any subset), OUT (results dir; reuse one to add steps)
set -euo pipefail
source "$(dirname "$0")/../scripts/lib.sh"
PROFILES="${PROFILES:-default mtp}"
STEPS=" ${STEPS:-ops bench mtp server} "
step() { [[ "$STEPS" == *" $1 "* ]]; }
OUT="${OUT:-$RESULTS/$(date +%Y%m%d-%H%M)-$(hostname -s)}"
mkdir -p "$OUT"
log "results -> $OUT"

stop_server() { podman rm -f inkling-server >/dev/null 2>&1 || true; }
trap stop_server EXIT
stop_server

{ echo "date: $(date -Is)"; echo "kernel: $(uname -r)"; echo "cmdline: $(cat /proc/cmdline)"
  echo "llama.cpp tree: $(git -C "$SRC" rev-parse 'HEAD^{tree}')"; echo "image: $(podman image inspect "$IMAGE" --format '{{.Id}}')"
  command -v tuned-adm >/dev/null && echo "tuned: $(tuned-adm active | awk -F': ' '{print $2}')"
  [ -r /sys/firmware/acpi/platform_profile ] && echo "platform_profile: $(cat /sys/firmware/acpi/platform_profile)"
  for z in /sys/class/thermal/thermal_zone*/temp; do [ -r "$z" ] && echo "$z: $(( $(cat "$z") / 1000 )) C"; done || true
} > "$OUT/environment.txt"

if step ops; then
  log "op correctness (test-backend-ops vs CPU)"
  "$ROOT/bench/test_ops.sh" "$OUT" || log "WARNING: some op tests failed, see $OUT/test-ops-*.log"
fi

if step bench; then
  log "llama-bench"
  "$ROOT/bench/llama_bench.sh" "$OUT"
fi

if step mtp && [[ " $PROFILES " == *" mtp "* ]]; then
  log "MTP head accuracy (teacher-forced)"
  "$ROOT/bench/mtp_check.sh" "$OUT"
fi

for p in $PROFILES; do
  step server || break
  log "server suite, profile $p"
  PROFILE=$p "$ROOT/scripts/serve.sh" > "$OUT/server-$p.log" 2>&1 &
  for _ in $(seq 180); do
    curl -sf "http://127.0.0.1:${PORT:-8732}/health" >/dev/null && break
    kill -0 $! 2>/dev/null || { tail -20 "$OUT/server-$p.log"; die "server ($p) exited during startup"; }
    sleep 5
  done
  curl -sf "http://127.0.0.1:${PORT:-8732}/health" >/dev/null || die "server ($p) not healthy after 15 min"
  inhibit python3 "$ROOT/bench/server_suite.py" "$OUT/server-$p.json" \
      --endpoint "http://127.0.0.1:${PORT:-8732}/v1/chat/completions"
  stop_server; wait 2>/dev/null || true; sleep 5
done

python3 "$ROOT/bench/compare.py" "$OUT" | tee "$OUT/summary.md"
