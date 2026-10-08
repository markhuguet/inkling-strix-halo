# Results: run-2026-10-08

| metric | reference | this run | Δ | verdict |
|---|---|---|---|---|
| llama-bench pp512 @0 | 297.3 | 297.3 | +0.0% | ok |
| llama-bench pp512 @8192 | 203.61 | 203.61 | +0.0% | ok |
| llama-bench tg64 @0 | 23.07 | 23.07 | +0.0% | ok |
| llama-bench tg64 @1024 | 19.13 | 19.13 | +0.0% | ok |
| llama-bench tg64 @16384 | 16.39 | 16.39 | +0.0% | ok |
| mtp depth 0 == target greedy | 0.349 | 0.349 | +0.0% | same |
| mtp depth 1 == target greedy | 0.027 | 0.027 | +0.0% | same |
| mtp depth 2 == target greedy | 0.023 | 0.023 | +0.0% | same |
| server[default] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[default] code_edit exact | True | True |  | same |
| server[default] code_edit tok/s | 82.87 | 82.87 | +0.0% | ok |
| server[default] decode_256 tok/s | 20.68 | 20.68 | +0.0% | ok |
| server[default] follow-up TTFT s | 3.14 | 3.14 | +0.0% | ok |
| server[default] prefill_10k tok/s | 247.7 | 247.7 | +0.0% | ok |
| server[default] prefill_2k tok/s | 279.8 | 279.8 | +0.0% | ok |
| server[default] story_400 sha256 | 6ce3dfb663aa516b | 6ce3dfb663aa516b |  | same |
| server[default] story_400 tok/s | 20.19 | 20.19 | +0.0% | ok |
| server[mtp] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[mtp] code_edit exact | True | True |  | same |
| server[mtp] code_edit tok/s | 80.71 | 80.71 | +0.0% | ok |
| server[mtp] decode_256 draft acceptance | 0.449 | 0.449 | +0.0% | same |
| server[mtp] decode_256 tok/s | 18.53 | 18.53 | +0.0% | ok |
| server[mtp] follow-up TTFT s | 4.05 | 4.05 | +0.0% | ok |
| server[mtp] prefill_10k tok/s | 238.3 | 238.3 | +0.0% | ok |
| server[mtp] prefill_2k tok/s | 254.2 | 254.2 | +0.0% | ok |
| server[mtp] story_400 draft acceptance | 0.485 | 0.485 | +0.0% | same |
| server[mtp] story_400 sha256 | 768bafe9aeda25e8 | 768bafe9aeda25e8 |  | same |
| server[mtp] story_400 tok/s | 20.63 | 20.63 | +0.0% | ok |
| test-backend-ops FLASH_ATTN_EXT_BANDED | 17/17 | 17/17 |  | same |
| test-backend-ops GET_ROWS | 216/216 | 216/216 |  | same |
| test-backend-ops MOE_ROUTE | 7/7 | 7/7 |  | same |
| test-backend-ops MUL_MAT | 1297/1297 | 1297/1297 |  | same |
| test-backend-ops MUL_MAT_ID | 929/929 | 929/929 |  | same |
| test-backend-ops OUT_PROD | 71/71 | 71/71 |  | same |
| test-backend-ops SSM_CONV | 45/45 | 45/45 |  | same |

All metrics reproduced (speed: within 10% or faster; acceptance/MTP accuracy: within 0.05; hashes/exactness: identical).
A differing story sha256 with the same tree, image and GPU usually means a different ROCm/kernel driver or GPU firmware: this model is numerically sensitive, so greedy text can change while quality does not.
