#!/bin/bash
# Configure and build the patched llama.cpp inside the container (HIP, gfx1151, Release).
# Targets: server, bench, perplexity, backend op tests, and the teacher-forced MTP checker.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ -d "$SRC/.git" ] || die "no llama.cpp checkout at $SRC (run scripts/fetch-llama.sh)"
TARGETS="${TARGETS:-llama-server llama-bench llama-perplexity llama-cli test-backend-ops}"
log "building $TARGETS in $SRC/$BUILD"
in_container -v "$SRC":/src -w /src -- bash -euc "
  [ -f $BUILD/build.ninja ] || cmake -S . -B $BUILD -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151 -DGGML_HIP_ROCWMMA_FATTN=OFF \
      -DGGML_NATIVE=ON -DLLAMA_BUILD_TESTS=ON -DLLAMA_CURL=OFF
  cmake --build $BUILD -j $JOBS --target $TARGETS
  # MTP accuracy checker (not part of upstream CMake): links libllama
  g++ -O2 -std=c++17 -Iinclude -Iggml/include tools/inkling-mtp-check/mtp-check.cpp \
      -L$BUILD/bin -lllama -lggml -lggml-base -Wl,-rpath,'\$ORIGIN' -o $BUILD/bin/llama-mtp-check
"
ls -la "$SRC/$BUILD/bin/llama-server" "$SRC/$BUILD/bin/llama-mtp-check"
