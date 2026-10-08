#!/bin/bash
# Build the dev/runtime image: Fedora 44 + TheRock ROCm 7.14.0 (gfx1151). ~3 GB download, ~10 GB image.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
log "building $IMAGE"
podman build --build-arg ROCM_TARBALL="$ROCM_TARBALL" -t "$IMAGE" -f "$ROOT/container/Containerfile" "$ROOT/container"
in_container -- bash -c 'hipcc --version | head -2; python3 -c "import numpy; print(\"numpy\", numpy.__version__)"'
