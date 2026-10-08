#!/bin/bash
# Reconstruct the exact llama.cpp source tree the results were measured on:
#   upstream master @ LLAMA_BASE  +  PR #25731 (squashed, as of LLAMA_PR_HEAD)  +  patches/0001..00NN
# and verify the final tree hash. Idempotent: an existing checkout at the expected tree is left alone.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

G=(git -C "$SRC" -c user.name=inkling-strix-halo -c user.email=inkling-strix-halo@localhost -c commit.gpgsign=false)

if [ -d "$SRC/.git" ] && [ "$("${G[@]}" rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$LLAMA_EXPECTED_TREE" ]; then
  log "llama.cpp already at the expected tree ($LLAMA_EXPECTED_TREE) in $SRC"
  exit 0
fi

if [ ! -d "$SRC/.git" ]; then
  log "cloning $LLAMA_REPO (blobless) into $SRC"
  mkdir -p "$WORK"
  git clone --filter=blob:none --no-checkout "$LLAMA_REPO" "$SRC"
elif [ -f "$SRC/.git/index" ]; then   # a --no-checkout clone has no index yet
  [ -z "$("${G[@]}" status --porcelain --untracked-files=no)" ] || die "$SRC has local changes; move it aside or set SRC=..."
fi

log "checking out upstream base $LLAMA_BASE"
"${G[@]}" fetch --quiet origin "$LLAMA_BASE" 2>/dev/null || true
"${G[@]}" checkout --quiet -B inkling-strix-halo "$LLAMA_BASE"

log "applying PR #$LLAMA_PR (squashed at ${LLAMA_PR_HEAD:0:9})"
"${G[@]}" apply --index --binary "$ROOT/patches/0000-pr25731-inkling-squashed.diff"
"${G[@]}" commit --quiet -m "PR #$LLAMA_PR: Inkling support (squashed at $LLAMA_PR_HEAD)"
tree=$("${G[@]}" rev-parse 'HEAD^{tree}')
[ "$tree" = "$LLAMA_PR_TREE" ] || die "PR tree mismatch: got $tree, expected $LLAMA_PR_TREE"

log "applying $(ls "$ROOT"/patches/*.patch | wc -l) local patches"
"${G[@]}" am --quiet --committer-date-is-author-date "$ROOT"/patches/[0-9][0-9][0-9][0-9]-*.patch

tree=$("${G[@]}" rev-parse 'HEAD^{tree}')
[ "$tree" = "$LLAMA_EXPECTED_TREE" ] || die "final tree mismatch: got $tree, expected $LLAMA_EXPECTED_TREE"
log "OK: $SRC is at tree $tree"
"${G[@]}" log --oneline -n 3 | cat
