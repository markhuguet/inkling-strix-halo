# Host setup

The reference machine is an HP ZBook Ultra G1a: Ryzen AI Max+ PRO 395, Radeon 8060S (gfx1151), 128 GB LPDDR5X-8000.
It runs Fedora 44 with kernel 7.2.7. Any Strix Halo machine with 128 GB should work.
Everything except the kernel parameters and podman runs inside a container, so the host distro matters little.

Run `scripts/check-host.sh` (or `make check`) at any point to see which of the items below are still missing.

## 1. BIOS: minimal dedicated VRAM

Set the UMA frame buffer, or "dedicated graphics memory", to its **minimum** (512 MB on the reference machine).
On Strix Halo the GPU reaches system RAM through GTT, so dedicated VRAM is memory taken away from the model.
The weights (92.7 GiB) and a 196K-token KV cache (~6 GiB) all live in GTT.

## 2. Kernel command line: let the GPU map ~124 GiB

By default, amdgpu caps GTT at about half of RAM. Raise the cap with these parameters:

```
amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856 amd_iommu=off
```

- `gttsize` is in MiB (124 GiB).
- `pages_limit` and `page_pool_size` are in 4 KiB pages (124 GiB).
- `amd_iommu=off` matches the reference machine. It is optional, but leaving the IOMMU on can cost a little GPU memory throughput.

On Fedora:

```bash
sudo grubby --update-kernel=ALL --args="amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856 amd_iommu=off"
sudo reboot
```

Check after the reboot. Expect ~133 GB GTT:

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

This leaves only ~4 GiB for the OS while the model is loaded. Close browsers and other large processes before serving.

## 3. GPU access and podman

```bash
sudo dnf install podman git          # or your distro's equivalent
sudo usermod -aG render,video "$USER" # then log out and back in
ls -l /dev/kfd                         # must be readable/writable by you
```

The containers run rootless with `--device /dev/kfd --device /dev/dri --group-add keep-groups`.
SELinux labelling is disabled per container (`--security-opt label=disable`) so they can read the bind-mounted model directory.

## 4. Power profile (affects the numbers)

The reference numbers were measured on AC power with:

```bash
sudo tuned-adm profile throughput-performance          # +6-7% prefill over "balanced"
cat /sys/firmware/acpi/platform_profile                  # "performance" (set by the vendor tool / BIOS / powerprofilesctl)
```

The scripts run long jobs under `systemd-inhibit`. A laptop suspend in the middle of a run silently ruins the results.

Thermals matter too. After hours of back-to-back runs the reference machine was ~10% slower than when it was cool.
Benchmark from a cool start for comparable numbers.

## 5. Disk

| what | size |
|---|---|
| container image | ~10 GB (podman storage) |
| llama.cpp checkout + build (`work/`) | ~2 GB |
| `UD-IQ3_XXS` GGUF + mmproj | 98 GB |
| `mtp.safetensors` | 4.5 GB |
| `UD-IQ3_XXS-MTP` | 2.4 GB on btrfs/xfs (reflink copies of the base shards); ~100 GB on other filesystems |

Weights go to `~/models/Inkling-Small-GGUF` by default. Set `MODELS=/path` for any script, or for `make`, to change it.
Use local NVMe: `--load-mode none` reads every byte into GTT at startup, which takes ~40 s from a fast SSD.
