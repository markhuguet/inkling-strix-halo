# Results: 20261007-2154-agileclanker

| metric | reference | this run | Δ | verdict |
|---|---|---|---|---|
| llama-bench pp512 @0 | 275.12 | 273.45 | -0.6% | ok |
| llama-bench pp512 @8192 | 188.61 | 187.24 | -0.7% | ok |
| llama-bench tg64 @0 | 20.35 | 20.44 | +0.4% | ok |
| llama-bench tg64 @1024 | 17.04 | 16.98 | -0.4% | ok |
| llama-bench tg64 @16384 | 14.45 | 14.8 | +2.4% | ok |
| mtp depth 0 == target greedy | 0.356 | 0.356 | +0.0% | same |
| mtp depth 1 == target greedy | 0.021 | 0.021 | +0.0% | same |
| mtp depth 2 == target greedy | 0.022 | 0.022 | +0.0% | same |
| server[default] code_edit draft acceptance | 0.935 | 0.935 | +0.0% | same |
| server[default] code_edit exact | True | True |  | same |
| server[default] code_edit tok/s | 74.99 | 75.3 | +0.4% | ok |
| server[default] decode_256 tok/s | 17.7 | 17.62 | -0.5% | ok |
| server[default] follow-up TTFT s | 3.4 | 3.4 | +0.0% | ok |
| server[default] prefill_10k tok/s | 225.7 | 225.0 | -0.3% | ok |
| server[default] prefill_2k tok/s | 255.8 | 251.7 | -1.6% | ok |
| server[default] story_400 sha256 | 29ecd29326cb0fac | 29ecd29326cb0fac |  | same |
| server[default] story_400 tok/s | 17.48 | 17.44 | -0.2% | ok |
| server[mtp] code_edit draft acceptance | 0.933 | 0.933 | +0.0% | same |
| server[mtp] code_edit exact | True | True |  | same |
| server[mtp] code_edit tok/s | 73.66 | 74.82 | +1.6% | ok |
| server[mtp] decode_256 draft acceptance | 0.435 | 0.435 | +0.0% | same |
| server[mtp] decode_256 tok/s | 17.94 | 17.75 | -1.1% | ok |
| server[mtp] follow-up TTFT s | 3.68 | 3.66 | -0.5% | ok |
| server[mtp] prefill_10k tok/s | 216.9 | 203.6 | -6.1% | ok |
| server[mtp] prefill_2k tok/s | 229.9 | 212.5 | -7.6% | ok |
| server[mtp] story_400 draft acceptance | 0.451 | 0.451 | +0.0% | same |
| server[mtp] story_400 sha256 | c2f23ea289fe777b | c2f23ea289fe777b |  | same |
| server[mtp] story_400 tok/s | 17.71 | 17.73 | +0.1% | ok |
| test-backend-ops FLASH_ATTN_EXT_BANDED | 17/17 | 17/17 |  | same |
| test-backend-ops GET_ROWS | 216/216 | 216/216 |  | same |
| test-backend-ops MUL_MAT | 1297/1297 | 1297/1297 |  | same |
| test-backend-ops MUL_MAT_ID | 929/929 | 929/929 |  | same |
| test-backend-ops SSM_CONV | 45/45 | 45/45 |  | same |

All metrics reproduced (speed: within 10% or faster; acceptance/MTP accuracy: within 0.05; hashes/exactness: identical).
A differing story sha256 with the same tree, image and GPU usually means a different ROCm/kernel driver or GPU firmware: this model is numerically sensitive, so greedy text can change while quality does not.
