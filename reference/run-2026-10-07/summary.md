# Results: run-2026-10-07

| metric | reference | this run | Δ | verdict |
|---|---|---|---|---|
| llama-bench pp512 @0 | 275.12 | 275.12 | +0.0% | ok |
| llama-bench pp512 @8192 | 188.61 | 188.61 | +0.0% | ok |
| llama-bench tg64 @0 | 20.35 | 20.35 | +0.0% | ok |
| llama-bench tg64 @1024 | 17.04 | 17.04 | +0.0% | ok |
| llama-bench tg64 @16384 | 14.45 | 14.45 | +0.0% | ok |
| mtp depth 0 == target greedy | 0.356 | 0.356 | +0.0% | same |
| mtp depth 1 == target greedy | 0.021 | 0.021 | +0.0% | same |
| mtp depth 2 == target greedy | 0.022 | 0.022 | +0.0% | same |
| server[default] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[default] code_edit exact | True | True |  | same |
| server[default] code_edit tok/s | 74.99 | 74.99 | +0.0% | ok |
| server[default] decode_256 tok/s | 17.7 | 17.7 | +0.0% | ok |
| server[default] follow-up TTFT s | 3.4 | 3.4 | +0.0% | ok |
| server[default] prefill_10k tok/s | 225.7 | 225.7 | +0.0% | ok |
| server[default] prefill_2k tok/s | 255.8 | 255.8 | +0.0% | ok |
| server[default] story_400 sha256 | 29ecd29326cb0fac | 29ecd29326cb0fac |  | same |
| server[default] story_400 tok/s | 17.48 | 17.48 | +0.0% | ok |
| server[mtp] code_edit draft acceptance | 0.933 | 0.933 | +0.0% | same |
| server[mtp] code_edit exact | True | True |  | same |
| server[mtp] code_edit tok/s | 73.66 | 73.66 | +0.0% | ok |
| server[mtp] decode_256 draft acceptance | 0.435 | 0.435 | +0.0% | same |
| server[mtp] decode_256 tok/s | 17.94 | 17.94 | +0.0% | ok |
| server[mtp] follow-up TTFT s | 3.68 | 3.68 | +0.0% | ok |
| server[mtp] prefill_10k tok/s | 216.9 | 216.9 | +0.0% | ok |
| server[mtp] prefill_2k tok/s | 229.9 | 229.9 | +0.0% | ok |
| server[mtp] story_400 draft acceptance | 0.451 | 0.451 | +0.0% | same |
| server[mtp] story_400 sha256 | c2f23ea289fe777b | c2f23ea289fe777b |  | same |
| server[mtp] story_400 tok/s | 17.71 | 17.71 | +0.0% | ok |
| test-backend-ops FLASH_ATTN_EXT_BANDED | 17/17 | 17/17 |  | same |
| test-backend-ops GET_ROWS | 216/216 | 216/216 |  | same |
| test-backend-ops MUL_MAT | 1297/1297 | 1297/1297 |  | same |
| test-backend-ops MUL_MAT_ID | 929/929 | 929/929 |  | same |
| test-backend-ops SSM_CONV | 45/45 | 45/45 |  | same |

All metrics reproduced (speed: within 10% or faster; acceptance/MTP accuracy: within 0.05; hashes/exactness: identical).
A differing story sha256 with the same tree, image and GPU usually means a different ROCm/kernel driver or GPU firmware: this model is numerically sensitive, so greedy text can change while quality does not.
