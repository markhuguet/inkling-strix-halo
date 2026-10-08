# What the patches change

`scripts/fetch-llama.sh` rebuilds the source tree in three layers and checks the git tree hash after each:

1. Upstream llama.cpp `master` at `7ab4ee7ba`.
2. **`patches/0000-pr25731-inkling-squashed.diff`**: [PR #25731](https://github.com/ggml-org/llama.cpp/pull/25731)
   (Inkling architecture support), squashed at its head `3870aa48b`. The PR was still open when this was measured.
   It is shipped as a diff so later force-pushes to the PR cannot change what you build.
3. **`patches/0001…0015`**: `git am` patches made on this machine.

Every runtime switch these patches add is listed at the bottom of this page.

| # | Patch | Why |
|---|---|---|
| 0001 | ROCm host-buffer workaround ([#25992](https://github.com/ggml-org/llama.cpp/pull/25992)) and the banded-FA MMA path on AMD WMMA | Upstream fix needed for loading on Strix Halo. The WMMA half is undone by 0002. |
| 0002 | Drop the AMD WMMA banded gate | The MMA instance the PR's banded attention needs has no RDNA3.5 device code, and enabling it crashes. |
| 0003 | **Split-K decode path** in `fattn-banded.cu` | The PR's AMD fallback is a one-warp-per-query loop over the whole KV cache, so decode collapsed with context (3.4 tok/s at 16K). Split-K brings 16K decode to ~13 tok/s. |
| 0004 | F32 output for F16 batched GEMMs on RDNA3 | First fix for the "`????`" garbage-output bug. Superseded by 0005, which reverts it. |
| 0005 | **Q6_K MoE banks always use MMQ on RDNA3** (reverts 0004) | Real root cause of the garbage output. Inkling's Q6_K shared-expert bank at ubatch 512 fell through to hipBLAS with F16 output, and its activations (~1e3) overflowed to inf. Prompts past ~4.6K tokens intermittently returned only `?`. |
| 0006 | **ALU sign handling for IQ2_S / IQ3_S**; SWAR `__vcmpne4` / `__vcmpeq4` on HIP | HIP emulated these per byte. Sign masks are now one multiply (`(b*0x00204081 & 0x01010101) * 0xFF`). Expert matvecs got ~2x faster; decode went 17.2 → 18.7, prefill 211 → 245. |
| 0007 | Split-K threshold 1024 → 64 keys | Between 256 and 1023 cached keys, decode was still on the slow kernel. |
| 0008 | Debug only: `GGML_CUDA_GRAPH_DEBUG`, `GGML_CUDA_GRAPH_FORCE_STALE` | Diagnosing why HIP graphs never engaged. |
| 0009 | Banded FA `kv_len` input (padded, graph-stable KV views) | Lets HIP graphs replay. Opt-in (`LLAMA_INKLING_PAD_KV=1`) because graph replay gave no speedup on ROCm 7.14. |
| 0010 | **Fused short conv** (concat → cpy → ssm_conv → add as one kernel, ≤ 8 tokens) | 4 short convs per layer: kernel launches per token 2944 → 2440. |
| 0011 | Banded attention mask built once per cache type | Was copied in every layer: 2440 → 2357 launches. |
| 0012 | mmvq reuses the quantized input across matvecs reading the same tensor | q/k/v/r and routed/shared experts read the same activations: 2357 → 2192 launches. |
| 0013 | **Tiled prompt kernel** for banded FA; optional `rel_idx` so wrapped sliding-window caches stay on the banded path | Prefill: pp512 @8K went 122 → ~180 tok/s. |
| 0014 | `INKLING_PERF_PP` perf set in `test-backend-ops` | Isolated benchmarks of Inkling's prompt-batch matmul shapes. |
| 0015 | **MTP depth heads and short-conv state rollback** | Loads the 8 MTP layers from the GGUF and builds the MTP graph. Recurrent short-conv state gets per-token snapshots (`n_rs_seq`), so a rejected speculative draft rolls back instead of replaying a checkpoint. This helps n-gram drafting too (code edit 70 → 78 tok/s). Also adds `tools/inkling-mtp-check`. |

## Runtime switches added by the patches

| env var | default | effect |
|---|---|---|
| `GGML_CUDA_BANDED_SPLIT_MIN` | 64 | minimum cached keys for the split-K decode kernel |
| `GGML_CUDA_BANDED_NO_TILED` | unset | disable the tiled prompt kernel |
| `GGML_CUDA_DISABLE_SCONV_FUSION` | unset | disable the fused short conv |
| `GGML_CUDA_NO_Q8_REUSE` | unset | disable mmvq quantized-input reuse |
| `LLAMA_INKLING_PAD_KV` | unset | padded KV views + device-side length (enables HIP graph replay) |
| `LLAMA_INKLING_NO_BANDED_IDX` | unset | wrapped sliding-window caches fall back to dense attention |
| `GGML_CUDA_GRAPH_DEBUG` | unset | log HIP/CUDA graph capture decisions |

Pass them to the server with `EXTRA_ENV="-e NAME=value"`.
