# Inkling-Small on Strix Halo

This repo runs Thinking Machines' **Inkling-Small** on one **AMD Ryzen AI Max+ 395 / Radeon 8060S (gfx1151) machine
with 128 GB**, using a patched llama.cpp on ROCm 7.14. Every input is pinned and each build step checks itself, so
another machine with the same hardware gets the same binaries, the same GGUF files and comparable numbers.

On the reference machine (HP ZBook Ultra G1a, AC power, `throughput-performance`):

| | PR #25731 alone¹ | this repo |
|---|---|---|
| decode, short context (llama-bench tg64) | 17.2 tok/s | **23.4 tok/s** |
| decode at 16K context | 3.4 tok/s | **15.7 tok/s** |
| prefill, pp512 / at 8K context | 211 / 122 tok/s | **299 / 196 tok/s** |
| server prefill, 9.8K-token prompt | 153 tok/s | **241 tok/s** |
| follow-up turn in a 9.8K conversation (TTFT) | 5.7 s | **3.3 s** |
| server decode / copy-heavy code edit (n-gram drafting) | 14.6 / 9.4 tok/s (no drafting) | **20.7 / 81 tok/s** |
| long prompts (> ~4.6K tokens) | intermittently only `?` | correct |

¹ PR #25731 plus the ROCm host-buffer fix it needs to load, same power profile, measured 2026-10-05.
Model: Unsloth `UD-IQ3_XXS` (97.9 GB); this repo serves it with its trunk requantized to Q5_K and its routers in F16
(`make trunk`, see below). 196K-token context, thinking off. The full reference run, with all logs, is in
[reference/run-2026-10-08-rf16/](reference/run-2026-10-08-rf16/summary.md).

The patches make decode **~5x faster at long context** than the open Inkling PR (#25731) alone, and fix an overflow that
made long prompts return only `?`.
[docs/RESULTS.md](docs/RESULTS.md) has the step-by-step history, and [docs/PATCHES.md](docs/PATCHES.md) explains each patch.

## Requirements

- Strix Halo (gfx1151) with **128 GB** RAM. The 3-bit weights alone are 92.7 GiB.
- Linux with these kernel parameters set, so the GPU can map ~124 GiB:
  `amdgpu.gttsize=126976 ttm.pages_limit=32505856 ttm.page_pool_size=32505856`.
  See [docs/SETUP.md](docs/SETUP.md).
- podman and git. Everything else (ROCm, compilers, Python) is inside the container.
- ~210 GB of disk on a fast local SSD: the 98 GB download plus the ~91 GB Q5_K-trunk model built from it (plus ~2.5 GB
  for MTP on btrfs/xfs, which reflink).

## Quick start

```bash
git clone https://github.com/markhuguet/inkling-strix-halo.git && cd inkling-strix-halo
scripts/check-host.sh           # PASS/WARN/FAIL for every prerequisite
make all                        # image -> source -> build -> 103 GB download -> Q5_K-trunk model -> MTP GGUF
make serve                      # http://127.0.0.1:8732  (OpenAI-compatible API + web UI)
```

`make all` runs these steps. Each one can be re-run safely and skips work that is already done and verified.

| step | script | what it does | time |
|---|---|---|---|
| `make image` | `scripts/build-image.sh` | Fedora 44 + TheRock ROCm 7.14.0 (gfx1151) image | ~5 min |
| `make source` | `scripts/fetch-llama.sh` | upstream llama.cpp @ `7ab4ee7ba` + PR #25731 + 15 patches; **checks the git tree hash** | <1 min |
| `make build` | `scripts/build-llama.sh` | HIP Release build in the container | ~10 min |
| `make weights` | `scripts/download-model.sh` | pinned HF revisions; **checks sha256** of every file | network |
| `make trunk` | `scripts/make-trunk-quant.sh` | builds the served model: the download's Q6_K trunk requantized to Q5_K with an importance matrix, routers to F16 (experts unchanged); **checks sha256** | ~15 min |
| `make mtp` | `scripts/make-mtp-gguf.sh` | adds the 8 MTP layers as a 4th GGUF shard; **checks sha256** (the conversion is deterministic) | ~3 min |

Weights go to `~/models/Inkling-Small-GGUF`. Set `MODELS=/elsewhere` to change it, e.g. `make MODELS=/data/inkling all`.

The served model is `UD-IQ3_XXS-trunk-q5_K-rf16`: the downloaded GGUF with two changes, and the experts unchanged.

- Its trunk (attention, shared experts, dense FFN) is Q5_K instead of Q6_K. That reads 8% fewer bytes per token, for
  +4–6% decode at a small quality cost (KLD +0.04).
- Its MoE routers are F16 instead of F32: about +1% decode, quality unchanged.

Details are in [docs/RESULTS.md](docs/RESULTS.md#decode-round-2-2026-10-08). `TRUNK_TYPE=none ROUTER_TYPE=none`
serves the download unchanged, and `TRUNK_TYPE=q4_K` gives a further +4% at a larger quality cost.

## Serving

```bash
make serve                  # PROFILE=default: n-gram speculative drafting
make serve-mtp              # PROFILE=mtp: n-gram first, then the MTP head (slower than default since 2026-10-08)
SLOTS=4 make serve          # 4 concurrent requests (~38 tok/s aggregate); adds --kv-unified automatically
CTX=65536 make serve        # smaller KV cache (default 196,608 tokens, ~6 GiB)
TEMPLATE_KWARGS='{"reasoning_effort":"low"}' make serve   # thinking on (default: none)
scripts/serve.sh --top-k 40 # extra arguments go to llama-server
```

```bash
curl -s http://127.0.0.1:8732/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":64}'
```

Image input works too: the vision projector (`mmproj-F16.gguf`) is loaded.

## Reproducing the results

Stop the server first (the GPU and memory must be free), then run:

```bash
make bench                  # = bench/run-all.sh, ~45 min
```

The run writes `results/<date>-<host>/` with every raw log, plus a `summary.md` that compares each metric with
`reference/reference-results.json`:

- **op correctness**: `test-backend-ops` on every op the patches touch, GPU against CPU. All tests must pass.
- **llama-bench**: decode tg64 at 0 / 1K / 16K context, prefill pp512 at 0 / 8K.
- **MTP head accuracy**, teacher-forced: `bench/mtp_check.sh`.
- **server suite** (`bench/server_suite.py`), per profile:
  - cold prefill at 2.4K and 9.8K tokens
  - 256-token decode
  - follow-up-turn TTFT
  - a 400-token greedy story (sha256 recorded)
  - a 1,383-token code edit, checked for an exactly correct output

How to read the verdicts:

- A speed counts as reproduced if it is within 10% of the reference, or faster.
- On identical hardware and software, greedy outputs usually match exactly.
- A different ROCm version, kernel driver or GPU firmware can change the story text without anything being wrong.
  This model is numerically sensitive (see [docs/RESULTS.md](docs/RESULTS.md#accuracy)).
- Expect ~10% lower numbers on a heat-soaked machine, on battery, or with the `balanced` profile.

To run only some parts: `STEPS="bench server" PROFILES=default bench/run-all.sh`.

## Performance test (2026-10-08)

This is the current reference: a full `make bench` on the reference machine, using the repo's own build. It ran on AC
power with `throughput-performance` and the default model (Q5_K trunk, F16 routers), starting at 63 °C.

**Server** (`bench/server_suite.py`, temperature 0, 196K context):

| | default profile (n-gram) | MTP profile (n-gram + MTP) |
|---|---|---|
| decode, 256 tokens | **20.7 tok/s** | 20.2 tok/s (44% of drafts accepted) |
| 400-token story | 20.0 tok/s | 20.1 tok/s (47% accepted) |
| code edit, 1,373 tokens | **80.5 tok/s**, output exactly correct | 79.9 tok/s, output exactly correct |
| prefill, 2.4K-token prompt | **273 tok/s** | 241 tok/s |
| prefill, 9.8K-token prompt | **241 tok/s** | 225 tok/s |
| follow-up turn in a 9.8K conversation (TTFT) | **3.3 s** | 3.5 s |

**Engine** (llama-bench, 3 repetitions):

| | short context | 1K | 8K | 16K |
|---|---|---|---|---|
| decode (tg64) | 23.4 tok/s | 19.2 | — | 15.7 |
| prefill (pp512) | 299 tok/s | — | 196 | — |

**Correctness:**

- `test-backend-ops`, GPU vs CPU: 2,582 / 2,582 tests pass (FLASH_ATTN_EXT_BANDED, SSM_CONV, MOE_ROUTE, OUT_PROD,
  MUL_MAT, MUL_MAT_ID, GET_ROWS).
- MTP head, teacher-forced agreement with the target's greedy token: depth 0 36%, depths 1-2 about 2-3%.

**Takeaway:** use the default profile. The MTP profile gives no decode gain, and it prefills more slowly.

**Compared with 2026-10-07** (Q6_K trunk, F32 routers, before patch 0016): server decode 17.7 → 20.7 (+17%), tg64
20.4 → 23.4 (+15%), prefill at 9.8K 226 → 241. Earlier runs are kept in `reference/run-2026-10-07/`,
`reference/rerun-2026-10-07/` and `reference/run-2026-10-08/` (Q5_K trunk with F32 routers).

## Repository layout

```
versions.env          every pinned input: llama.cpp commits + expected tree hashes, ROCm tarball, HF revisions
container/            Containerfile (Fedora 44 + TheRock ROCm 7.14.0)
patches/              0000 = PR #25731 squashed; 0001-0017 = the local patch series (git am)
scripts/              host check, image, source, build, weights, MTP GGUF, serve
tools/convert_mtp.py  mtp.safetensors -> 4th GGUF shard
bench/                run-all.sh, llama_bench.sh, test_ops.sh, mtp_check.sh, server_suite.py, compare.py, data/
reference/            sha256 of downloads and of the generated MTP GGUF; reference-results.json; reference run
docs/                 SETUP (host), PATCHES (what/why), RESULTS (history, rejected ideas), MTP
```

## Known limitations

- **gfx1151 only.** The build targets gfx1151, and the kernel tuning was measured only there. Other RDNA3 GPUs would
  need `AMDGPU_TARGETS` changed and re-validation.
- **PR #25731 is unmerged upstream.** These patches sit on a fixed snapshot of it. Expect conflicts if you rebase onto
  a newer llama.cpp.
- **Multiple slots require `--kv-unified`** (added automatically). Batched decode produces different text than single
  requests, which is normal.
- **MTP helps little with a 3-bit target** (~36-43% depth-0 agreement). See [docs/MTP.md](docs/MTP.md).
- **The Q5_K-trunk model is bit-reproducible only if the imatrix run is.** Its sha256 is pinned in `reference/`.
  A mismatch on other hardware still gives an equivalent model; check it with KLD.
- **Capability results are not reproducible from this repo.** The fixture corpus was built from private code.

## Troubleshooting

| symptom | cause / fix |
|---|---|
| `check-host.sh`: GTT < 118 GiB | kernel parameters not applied; see docs/SETUP.md §2 |
| load fails / OOM at startup | another GPU process holds GTT (`podman ps`, close browsers), or `CTX` is too large |
| output is only `?` | you are running an unpatched build; `make source build` |
| `fetch-llama.sh`: tree mismatch | a patch file was modified; restore it with `git checkout patches/` |
| sha256 mismatch after download | partial or corrupt file; delete it and re-run `make weights` |
| 1-2 tok/s with `SLOTS>1` | `--kv-unified` missing (only happens if you call llama-server yourself) |
| numbers ~10% low | heat soak, battery, or `balanced` power profile; see docs/SETUP.md §4 |

## License

This repository (scripts, tools, benchmarks, docs) is licensed under the **GNU General Public License v2.0 only** (GPL-2.0-only).
See [LICENSE](LICENSE).

Exceptions:

- `patches/` modify [llama.cpp](https://github.com/ggml-org/llama.cpp) and stay under llama.cpp's **MIT license**,
  so they can be contributed upstream.
- `patches/0000-pr25731-inkling-squashed.diff` is the work of the PR #25731 authors.
- The model weights are not included. They are downloaded from their own repositories under their own licenses:
  [unsloth/Inkling-Small-GGUF](https://huggingface.co/unsloth/Inkling-Small-GGUF) and
  [thinkingmachines/Inkling-Small](https://huggingface.co/thinkingmachines/Inkling-Small).
