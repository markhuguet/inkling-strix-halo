#!/bin/bash
# Check that this machine can hold and run Inkling-Small the way the reference results were measured.
# Prints PASS/WARN/FAIL per item; exits non-zero on any FAIL.
source "$(dirname "$0")/lib.sh"
fails=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fails=$((fails + 1)); }

echo "GPU"
if grep -qs 'gfx_target_version 110501' /sys/class/kfd/kfd/topology/nodes/*/properties; then
  pass "gfx1151 (Strix Halo / Radeon 8060S) present"
else
  fail "no gfx1151 GPU found in /sys/class/kfd (the build and kernels target gfx1151 only)"
fi
[ -r /dev/kfd ] && [ -w /dev/kfd ] && pass "/dev/kfd accessible" || fail "/dev/kfd not read/writable (add yourself to the render group)"

echo "Memory"
mem_gib=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
[ "$mem_gib" -ge 120 ] && pass "RAM ${mem_gib} GiB" || fail "RAM ${mem_gib} GiB: the 3-bit weights alone are 92.7 GiB; needs a 128 GB machine"
gtt=0
for f in /sys/class/drm/card*/device/mem_info_gtt_total; do [ -r "$f" ] && gtt=$(( $(cat "$f") > gtt ? $(cat "$f") : gtt )); done
gtt_gib=$((gtt / 1073741824))
if [ "$gtt_gib" -ge 118 ]; then
  pass "GPU-addressable GTT ${gtt_gib} GiB"
else
  fail "GTT only ${gtt_gib} GiB; need ~120 GiB. Add to the kernel command line (see docs/SETUP.md):
         amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856"
fi
grep -qw 'amd_iommu=off' /proc/cmdline && pass "amd_iommu=off" || warn "amd_iommu=off not set (reference machine had it; may cost a few % on GPU memory access)"

echo "Software"
command -v podman >/dev/null && pass "podman $(podman --version | awk '{print $3}')" || fail "podman not installed"
command -v git >/dev/null && pass "git" || fail "git not installed"
if podman image exists "$IMAGE" 2>/dev/null; then pass "image $IMAGE built"; else warn "image $IMAGE not built yet (scripts/build-image.sh)"; fi

echo "Power / thermals"
if command -v tuned-adm >/dev/null; then
  prof=$(tuned-adm active 2>/dev/null | awk -F': ' '{print $2}')
  [ "$prof" = "throughput-performance" ] && pass "tuned profile $prof" \
    || warn "tuned profile '$prof'; reference numbers used throughput-performance (+6-7% prefill vs balanced)"
fi
if [ -r /sys/firmware/acpi/platform_profile ]; then
  pp=$(cat /sys/firmware/acpi/platform_profile)
  [ "$pp" = "performance" ] && pass "ACPI platform profile $pp" || warn "ACPI platform profile '$pp' (reference: performance)"
fi
grep -qs 1 /sys/class/power_supply/A*/online && pass "on AC power" || warn "not on AC power (or unknown): expect lower numbers"

echo "Disk"
mkdir -p "$MODELS" 2>/dev/null || true
free_gb=$(df -BG --output=avail "$MODELS" 2>/dev/null | tail -1 | tr -dc 0-9)
[ "${free_gb:-0}" -ge 110 ] && pass "${free_gb} GB free at $MODELS" \
  || warn "${free_gb:-?} GB free at $MODELS: need ~105 GB for UD-IQ3_XXS (+2.5 GB MTP shard with reflinks, +100 GB without)"
fstype=$(stat -f -c %T "$MODELS" 2>/dev/null)
case "$fstype" in btrfs|xfs) pass "$fstype: MTP GGUF shares the base shards via reflink copies" ;;
  *) warn "filesystem '$fstype' has no reflinks: the MTP GGUF will be a full ~100 GB copy" ;; esac

[ "$fails" -eq 0 ] && echo "host OK" || { echo "$fails check(s) failed"; exit 1; }
