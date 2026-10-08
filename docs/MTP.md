# Multi-token prediction (MTP)

Inkling-Small ships 8 MTP "depth" layers in `mtp.safetensors`, separate from the main checkpoint. Unsloth's GGUFs leave
them out. `tools/convert_mtp.py` appends them to the 3-shard GGUF as a 4th shard: Q8_0 matrices, F32 norms and convs.
It rewrites shard 1's metadata (`block_count` 42 → 50, `inkling.nextn_predict_layers = 8`, per-layer arrays extended)
and patches the split counts of shards 2 and 3 in place.

## What each depth computes

The patches implement each depth to match vLLM's reference:

```
x_d = input_proj( concat[ hidden_norm(h_prev) , embed_norm(backbone_embed_norm(embed(token))) ] )   # 8192 -> 4096
h_d = InklingDecoderLayer_d(x_d)          # dense MLP; depths 0,2,4,5,6,7 sliding-window, 1,3 global
logits_d = lm_head(h_d) / mup             # shared head, no final norm
```

- Depth 0 takes the target's **post-final-norm** hidden state as `h_prev`. Depth d > 0 takes depth d−1's raw output.
- The concat order is `[hidden | embed]`. Swapping it drops acceptance to 0%.

## Measured

| | result |
|---|---|
| teacher-forced, depth 0 == target greedy | 36% on `bench/data/mtp_text.txt` (1,024 tokens); 42-43% on shorter samples. Q8_0 and F16 heads score the same |
| teacher-forced, depth ≥ 1 | ~2% |
| server acceptance, 1 draft token, prose | 45% |
| server acceptance, 1 draft token, code edit | 92% |

Depth 0 agreeing with the target only ~36-43% of the time is the limiting factor. The likely cause is that the heads were
trained on BF16 hidden states, and the 3-bit target's hidden states differ from those. This has not been verified.
A higher-precision target would probably accept more drafts, but it does not fit in 128 GB.

Because depths ≥ 1 are almost never right, drafting more than one token is pointless here (`--spec-draft-n-max 1`).

## Status (2026-10-08): not worth it

After the decode fusions (patch 0016) and the Q5_K trunk, the default profile decodes at 20.7 tok/s and the MTP
profile at 18.5. MTP also prefills more slowly and has a slower follow-up TTFT (see the README performance test).
The faster each token gets, the less a 45%-accepted 1-token draft can win back, while every draft still costs a
verify step that reads the union of both tokens' experts. The numbers below are from 2026-10-07.

## Why `PROFILE=mtp` runs n-gram first

With one draft token, MTP can at most double decode speed. On copy-heavy output (code edits, quoting), n-gram drafting
proposes long runs and reaches 78 tok/s, while MTP alone reaches 23. `--spec-type ngram-simple,draft-mtp` tries n-gram
first and falls back to MTP only when n-gram has no match:

| profile | story (400 tok) | code edit (1383 tok) |
|---|---|---|
| default (n-gram) | 18.0 | 78.2 |
| MTP only | 18.4 | 22.7 |
| n-gram + MTP | 18.7 | 80.4 |

The gain is small: about +4% on prose. It also has a cost: the MTP layer processes every prompt too, so cold
prefill is ~5-10% slower (reference run: 230 vs 256 tok/s at 2.4K tokens, 217 vs 226 at 9.8K).

## Rollback, and a determinism caveat

Inkling's short convolutions carry recurrent state. When a draft token is rejected, that state must be rewound.
Before patch 0015 the server restored a full checkpoint and re-ran the batch, which made MTP *slower* than no MTP
(13.9 vs 17.6 tok/s). Patch 0015 keeps per-token conv-state snapshots (`n_rs_seq`) and gives the MTP draft context the
same rollback depth as the target.

At temperature 0, the MTP profile's story text diverges from the default profile's after ~700 characters. The
divergence is the same on every run. The code-edit output is byte-identical. The likely cause is that verifying 2
tokens per batch takes different GPU kernel paths than decoding 1 token, and this model is numerically sensitive:
correct kernels differ from each other by KL ≈ 0.1. This explanation is not proven.

## Checking the heads yourself

```bash
bench/mtp_check.sh results/mtp      # teacher-forced accuracy per depth on bench/data/mtp_text.txt
```
