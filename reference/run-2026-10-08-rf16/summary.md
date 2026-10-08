# Results: run-2026-10-08-rf16

| metric | reference | this run | Δ | verdict |
|---|---|---|---|---|
| llama-bench pp512 @0 | 298.59 | 298.59 | +0.0% | ok |
| llama-bench pp512 @8192 | 196.11 | 196.11 | +0.0% | ok |
| llama-bench tg64 @0 | 23.35 | 23.35 | +0.0% | ok |
| llama-bench tg64 @1024 | 19.23 | 19.23 | +0.0% | ok |
| llama-bench tg64 @16384 | 15.66 | 15.66 | +0.0% | ok |
| mtp depth 0 == target greedy | 0.358 | 0.358 | +0.0% | same |
| mtp depth 1 == target greedy | 0.023 | 0.023 | +0.0% | same |
| mtp depth 2 == target greedy | 0.026 | 0.026 | +0.0% | same |
| server[default] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[default] code_edit exact | True | True |  | same |
| server[default] code_edit tok/s | 80.54 | 80.54 | +0.0% | ok |
| server[default] decode_256 tok/s | 20.66 | 20.66 | +0.0% | ok |
| server[default] follow-up TTFT s | 3.32 | 3.32 | +0.0% | ok |
| server[default] prefill_10k tok/s | 240.6 | 240.6 | +0.0% | ok |
| server[default] prefill_2k tok/s | 272.6 | 272.6 | +0.0% | ok |
| server[default] story_400 sha256 | b95bcbaca876fc10 | b95bcbaca876fc10 |  | same |
| server[default] story_400 tok/s | 19.96 | 19.96 | +0.0% | ok |
| server[mtp] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[mtp] code_edit exact | True | True |  | same |
| server[mtp] code_edit tok/s | 79.87 | 79.87 | +0.0% | ok |
| server[mtp] decode_256 draft acceptance | 0.443 | 0.443 | +0.0% | same |
| server[mtp] decode_256 tok/s | 20.21 | 20.21 | +0.0% | ok |
| server[mtp] follow-up TTFT s | 3.5 | 3.5 | +0.0% | ok |
| server[mtp] prefill_10k tok/s | 225.3 | 225.3 | +0.0% | ok |
| server[mtp] prefill_2k tok/s | 240.6 | 240.6 | +0.0% | ok |
| server[mtp] story_400 draft acceptance | 0.469 | 0.469 | +0.0% | same |
| server[mtp] story_400 sha256 | f6352cf6ecd52e40 | f6352cf6ecd52e40 |  | same |
| server[mtp] story_400 tok/s | 20.09 | 20.09 | +0.0% | ok |
| test-backend-ops FLASH_ATTN_EXT_BANDED | 17/17 | 17/17 |  | same |
| test-backend-ops GET_ROWS | 216/216 | 216/216 |  | same |
| test-backend-ops MOE_ROUTE | 7/7 | 7/7 |  | same |
| test-backend-ops MUL_MAT | 1297/1297 | 1297/1297 |  | same |
| test-backend-ops MUL_MAT_ID | 929/929 | 929/929 |  | same |
| test-backend-ops OUT_PROD | 71/71 | 71/71 |  | same |
| test-backend-ops SSM_CONV | 45/45 | 45/45 |  | same |

All metrics reproduced (speed: within 10% or faster; acceptance/MTP accuracy: within 0.05; hashes/exactness: identical).
A differing story sha256 with the same tree, image and GPU usually means a different ROCm/kernel driver or GPU firmware: this model is numerically sensitive, so greedy text can change while quality does not.
