#!/usr/bin/env python3
"""Write a llama-quantize --tensor-type-file that pins EVERY tensor to its current type (so llama-quantize copies it
unchanged) except Q6_K trunk tensors, which go to TRUNK_TYPE, optionally output.weight -> HEAD_TYPE, and optionally the
F32 MoE routers (blk.N.ffn_gate_inp) -> ROUTER_TYPE (e.g. f16; needs llama-quantize's explicit-override support).

  gen_types.py GGUF_DIR OUT.txt TRUNK_TYPE [HEAD_TYPE|-] [ROUTER_TYPE]
"""
import glob, re, sys
from gguf import GGUFReader

src, out, trunk_type = sys.argv[1:4]
head_type = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "-" else None
router_type = sys.argv[5] if len(sys.argv) > 5 else None
TRUNK = {"attn_q", "attn_output", "attn_k", "attn_v", "ffn_gate_shexp", "ffn_up_shexp", "ffn_down_shexp",
         "ffn_gate", "ffn_up", "ffn_down"}
lines, changed = [], 0
for f in sorted(glob.glob(src + "/*.gguf")):
    for t in GGUFReader(f).tensors:
        cur = t.tensor_type.name.lower()
        new = cur
        m = re.match(r"blk\.\d+\.(\w+)\.weight$", t.name)
        if m and m.group(1) in TRUNK and cur == "q6_k":
            new = trunk_type
        if t.name == "output.weight" and head_type:
            new = head_type
        if m and m.group(1) == "ffn_gate_inp" and router_type and cur == "f32":
            new = router_type
        changed += new != cur
        if cur in ("f32", "f16", "bf16") and new == cur:
            continue  # unquantized tensors (norms, convs, router) are copied as-is anyway
        lines.append("^" + re.escape(t.name).replace("\\_", "_") + "$=" + new)
open(out, "w").write("\n".join(lines) + "\n")
print(f"{len(lines)} pinned, {changed} retyped -> {out}")
