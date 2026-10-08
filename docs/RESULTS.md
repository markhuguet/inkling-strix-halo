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

## Decode round 2 (2026-10-08)

**Floor.** A decoded token reads 6.12 GiB of weights. That is 32–35 tok/s at a realistic 210–230 GB/s, against
20.4 measured. The PMC profile showed that the large matvecs were already at 195–247 GB/s. The gap was ~1,450 small
kernel launches per token at ~6–7 µs each.

**Trunk requant (default since this round).** The Q6_K trunk tensors (attention, shared experts, dense FFN) were
requantized with an importance matrix computed from the downloaded model. The 287 tensors moved are listed in
`work/trunk-quant/types-*.txt`, and the experts stay byte-identical. Recipe: `scripts/make-trunk-quant.sh`.

| trunk | tg64 @0 | tg64 @4K | server decode | KLD vs f32 CPU ref | same top token |
|---|---|---|---|---|---|
| Q6_K (download) | 19.6 | 16.1 | 17.6 | 0.168 | 88.6% |
| **Q5_K (default)** | 20.9 | 17.0 | 18.3 | 0.208 | 86.4% |
| Q4_K | 21.8 | 17.8 | 19.2 | 0.284 | 83.7% |

Both requants keep the code edit exact. Q5_K adds about +0.04 KLD, Q4_K about +0.12. `TRUNK_TYPE=q4_K` or `none`
selects the others.

**Fusion (patch 0016).** Dispatches per token went 2192 → 1438. On the Q5_K trunk, tg64 went 21.1 → 22.7 at 0
(+7.7%) and 17.3 → 18.4 at 4K (+6.4%); server decode went 18.3 → 19.7. Decode output is bit-identical except for
the routing math, whose KLD is unchanged (0.164 vs 0.168).

**F16 routers (default since 2026-10-08, patch 0017).** `ffn_gate_inp` was stored as F16 instead of F32, halving
the 161 MB router read per token. The router matvec went 1.41 → 0.97 ms per token; it is latency-bound at ~90 GB/s
because 258 rows is too small a matrix. tg64 changed by +0.3% at 0 and +1.3% at 4K. KLD vs the f32 CPU reference was
0.205 against 0.218 for F32 routers (noise), and the same top token was 86.6% against 86.5%.

**Fusion round 2 (rejected).** Three more fusions were bit-identical: the K/V cache writes as one launch, the
shared-expert adds folded into the expert reduction, and the layer close reordered so the residual fuses. Together
they removed ~120 launches per token, but tg64 moved −0.7% at 0 and +0.3% at 4K, within noise. Fusing the q/k RMS
norms as one kernel was not bit-identical. With ~1,000 launches per token left, they overlap with GPU work, and
removing more no longer saves measurable time.

**Matvec launch shape (rejected).** gfx1151 used the RDNA2 mmvq table, which gives 1 warp per block. A dedicated
RDNA3.5 table was swept, and every setting landed within ±1%; 2–4 warps for the IQ types was worse. The remaining
expert-kernel headroom is ~3%.

**Where the time goes now** (per token): matvecs ~29 ms, at 190–220 GB/s. The remaining small kernels are:

| kernel | count per token | time |
|---|---|---|
| quantize_q8_1 | 249 | 1.7 ms |
| rms_norm | 170 | 1.4 ms |
| short conv | 168 | 1.3 ms |
| bin_bcast (adds, muls) | 139 | 1.0 ms |
| set_rows | 84 | 0.6 ms |

The F32 router matvec is another 1.4 ms, at only ~120 GB/s. The GPU also runs at ~2.4 GHz of its 2.9 GHz maximum
during decode.

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
- **ROCm 10.1** (HIP 7.16, clang 24; `container/Containerfile.rocm10`, 2026-10-08): all op tests pass, but decode is
  unchanged (23.2 vs 23.4 tok/s at 0, 18.7 vs 18.5 at 4K) and prefill is 2–3% slower. HIP graphs are still slower
  than plain launches. The ~6 µs per-launch cost doesn't come from the user-space runtime.
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
