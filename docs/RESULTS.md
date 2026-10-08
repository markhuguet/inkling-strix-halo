# How the speed was found

The work was done 2026-10-05 → 2026-10-07 on the reference machine (see [SETUP.md](SETUP.md)).
`reference/reference-results.json` holds the numbers that `bench/run-all.sh` compares against.
This page records how they were reached, including what was tried and rejected.

## Starting point: PR #25731 as-is (+ ROCm host-buffer fix)

| | |
|---|---|
| decode, llama-bench tg64 | 17.2 tok/s @0, 3.4 @16K |
| prefill, llama-bench pp512 | 211 tok/s @0, 122 @8K |
| server decode | 14.6 tok/s; 4.1 @12.6K context; 2.4 @25K |
| server prefill | 192 tok/s @3K, 84 @25K |
| correctness | prompts past ~4.6K tokens intermittently returned only `?` |

Why it was slow: the PR's banded flash attention (attention with relative-position bias) takes its fast MMA kernel
only on NVIDIA. On gfx1151 it fell back to a scalar kernel looping over the whole KV cache, so both prefill and decode
degraded with context.

## Steps, in order

| step | patch | effect |
|---|---|---|
| server flags: `throughput-performance`, `--spec-type ngram-simple` | — | +6-7% prefill; code edit 10 → 57 tok/s (output identical at temp 0) |
| split-K banded decode | 0003 | decode @16K 3.4 → 12.9 tok/s |
| Q6_K MoE → MMQ (overflow fix) | 0005 | `?`-only outputs gone; replaces a blanket F32-output fix that cost 13-19% prefill |
| IQ2_S/IQ3_S sign tricks | 0006 | expert matvecs ~2x; tg64 17.2 → 18.7, pp512 211 → 245 |
| split-K from 64 keys | 0007 | decode @512 ctx 10.5 → 16.6; server long-answer decode 11.6 → 16.6 |
| fused short conv | 0010 | tg64 18.7 → 19.6 |
| mask once per cache type | 0011 | tg64 19.6 → 20.3 |
| mmvq input reuse | 0012 | tg64 20.2 → 20.5 |
| tiled prompt kernel + `rel_idx` | 0013 | pp512 @8K 122 → ~180; server prefill @9.8K 160 → 225 |
| conv-state rollback | 0015 | n-gram code edit 70 → 78; makes MTP viable |
| MTP heads (n-gram + MTP) | 0015 | prose decode +4%, code edit 80 |

## Tried and rejected (measured, no gain)

- **HIP graphs** (patch 0009, opt-in `LLAMA_INKLING_PAD_KV=1`): graphs replay correctly, but on ROCm 7.14 replaying
  ~2,900 nodes costs about the same as launching them. An apparent +8% "ceiling" was an artifact of stale replays doing
  less work.
- **MMQ tile-config sweep** for IQ2_S/IQ3_S/Q6_K (stream-K, row widths, occupancy): up to −24% in isolation,
  no change in the model.
- **mmvq launch tables**: a few percent either way.
- **ubatch 1024/2048**: +5-10% cold prefill. But follow-up turns re-process 2-4x more tokens (TTFT 3.5 s → 10.7 s),
  so 512 was kept.
- **4 experts instead of 6**: +4% decode. Rejected as a quality risk.
- **UD-Q2_K_XL**: +2% decode, +6-10% prefill, 10 GB smaller. Its experts are still i-quants. Quality was not measured,
  so UD-IQ3_XXS stays the reference.
- **MTP drafting more than 1 token**: depths ≥ 1 agree with the target ~2% of the time.

## Where decode time goes now

Profiled with rocprofv3 PMC counters. The GPU is busy ~86% of each decode step:

| | share of busy time | bandwidth |
|---|---|---|
| Q6_K trunk projections | ~26% | 170-230 GB/s |
| IQ2_S expert gate/up | ~19% | ~110 GB/s |
| IQ3_S expert down | ~11% | ~135 GB/s |
| tiny kernels (norms, adds, ...) | ~13% | |
| output head | ~4% | |

Expert weights are "cold": each token touches 6 of 256 experts, so expert reads miss the L2 (~15% hit rate).

## Multi-request serving

`SLOTS=N` needs `--kv-unified`, which `serve.sh` adds automatically. Per-slot KV streams knock attention off the banded
path, giving a 40 GB compute buffer and 1.5 tok/s.

| slots | concurrent requests | aggregate decode | per request |
|---|---|---|---|
| 1 | 1 | ~17.5 tok/s | 17.5 |
| 2 | 2 | 26.3 | 13.6 |
| 4 | 4 | 38.2 | 9.9 |

## Accuracy

- `llama-perplexity` agrees with an f32 CPU reference to within run-to-run noise. All GPU variants show KLD
  0.163-0.174 against the CPU reference, with the same top token 88.6-88.9% of the time.
- The model is numerically sensitive: two *correct* GPU kernel variants differ from each other by KLD ~0.11-0.13.
  Expect greedy text to change whenever kernels, ROCm or batch shapes change.
- A capability check was also run on a private symbol-localisation corpus (92% correct, 0 garbage outputs).
  It is not included here because the corpus is built from private code.
