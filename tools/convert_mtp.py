#!/usr/bin/env python3
"""Add Inkling-Small's 8 MTP depth layers (mtp.safetensors) to an existing 3-shard Inkling GGUF as a 4th shard.

  convert_mtp.py SRC_DIR SRC_PREFIX MTP_SAFETENSORS DST_DIR DST_PREFIX

- shard 1 (metadata) is rewritten: block_count += 8, inkling.nextn_predict_layers = 8, the sliding-window pattern
  gets the MTP depths' local flags appended, split.count = 4, split.tensors.count += n_mtp.
- shards 2..3 must already exist in DST_DIR as copies (reflinks) named DST_PREFIX-0000N-of-00004.gguf; only their
  split.count / split.tensors.count values are patched in place.
- shard 4 holds blk.{n_layer + i}.* for MTP depth i, in the same layout/types as the converter uses for the dense
  backbone layers, plus nextn.{eh_proj,enorm,hnorm}. Matrices Q8_0, norms / short convs / rel proj / gscale F32.
"""
import json, struct, sys
import numpy as np
import gguf
from gguf import GGUFReader, GGUFWriter, GGMLQuantizationType as QT

src_dir, src_prefix, mtp_path, dst_dir, dst_prefix = sys.argv[1:6]
SRC = lambda n: f"{src_dir}/{src_prefix}-{n:05d}-of-00003.gguf"
DST = lambda n: f"{dst_dir}/{dst_prefix}-{n:05d}-of-00004.gguf"
ARCH = "inkling"
MTP_LOCAL_IDS = {0, 2, 4, 5, 6, 7}   # config.json mtp_config.local_layer_ids
N_MTP = 8

# ---- read mtp.safetensors (BF16) without torch ----
def read_safetensors(path):
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        hdr = json.loads(f.read(n))
        base = 8 + n
        out = {}
        for k, v in hdr.items():
            if k == "__metadata__":
                continue
            assert v["dtype"] == "BF16", (k, v["dtype"])
            a, b = v["data_offsets"]
            f.seek(base + a)
            u16 = np.frombuffer(f.read(b - a), dtype=np.uint16).reshape(v["shape"])
            out[k] = (u16.astype(np.uint32) << 16).view(np.float32)
        return out

mtp = read_safetensors(mtp_path)

# ---- shard 1 metadata ----
r1 = GGUFReader(SRC(1))
def field_val(r, key):
    f = r.fields[key]
    return f.contents()
n_layer = int(field_val(r1, f"{ARCH}.block_count"))
n_tensors_old = int(field_val(r1, "split.tensors.count"))

def mtp_tensors():
    """Yield (gguf_name, np.float32 array, target type) for every MTP tensor."""
    for i in range(N_MTP):
        p = f"model.mtp.layers.{i}."
        tb = p + "transformer_block."
        b = f"blk.{n_layer + i}."
        yield b + "nextn.eh_proj.weight", mtp[p + "input_proj.weight"], QT.Q8_0
        yield b + "nextn.enorm.weight",   mtp[p + "embed_norm.weight"], QT.F32
        yield b + "nextn.hnorm.weight",   mtp[p + "hidden_norm.weight"], QT.F32
        yield b + "attn_q.weight",        mtp[tb + "attn.wq_du.weight"], QT.Q8_0
        yield b + "attn_k.weight",        mtp[tb + "attn.wk_dv.weight"], QT.Q8_0
        yield b + "attn_v.weight",        mtp[tb + "attn.wv_dv.weight"], QT.Q8_0
        yield b + "attn_output.weight",   mtp[tb + "attn.wo_ud.weight"], QT.Q8_0
        yield b + "attn_r.weight",        mtp[tb + "attn.wr_du.weight"], QT.Q8_0
        yield b + "attn_rel_proj.weight", mtp[tb + "attn.rel_logits_proj.proj"], QT.F32
        yield b + "attn_q_norm.weight",   mtp[tb + "attn.q_norm.weight"], QT.F32
        yield b + "attn_k_norm.weight",   mtp[tb + "attn.k_norm.weight"], QT.F32
        yield b + "attn_norm.weight",     mtp[tb + "attn_norm.weight"], QT.F32
        yield b + "ffn_norm.weight",      mtp[tb + "mlp_norm.weight"], QT.F32
        w13 = mtp[tb + "mlp.w13_dn.weight"]                 # interleaved rows: gate = 0::2, up = 1::2
        yield b + "ffn_gate.weight",      np.ascontiguousarray(w13[0::2, :]), QT.Q8_0
        yield b + "ffn_up.weight",        np.ascontiguousarray(w13[1::2, :]), QT.Q8_0
        yield b + "ffn_down.weight",      mtp[tb + "mlp.w2_md.weight"], QT.Q8_0
        yield b + "ffn_gscale.weight",    mtp[tb + "mlp.global_scale"].reshape(1), QT.F32
        for src, dst in (("attn.k_sconv", "shortconv_k"), ("attn.v_sconv", "shortconv_v"),
                         ("attn_sconv", "shortconv_attn"), ("mlp_sconv", "shortconv_mlp")):
            yield b + dst + ".weight", np.ascontiguousarray(mtp[tb + src + ".weight"].squeeze(1)), QT.F32

n_mtp = sum(1 for _ in mtp_tensors())
assert n_mtp == 21 * N_MTP, n_mtp
n_total = n_tensors_old + n_mtp

# ---- write new shard 1: same KV with the MTP edits, same tensors ----
w1 = GGUFWriter(DST(1), ARCH, use_temp_file=False)
skip = {"GGUF.version", "GGUF.tensor_count", "GGUF.kv_count", "general.architecture"}
for key, f in r1.fields.items():
    if key in skip:
        continue
    vtype = f.types[0]
    val = f.contents()
    if key == f"{ARCH}.block_count":
        val = n_layer + N_MTP
    elif key == "split.count":
        val = 4
    elif key == "split.tensors.count":
        val = n_total
    elif key == f"{ARCH}.attention.sliding_window_pattern":
        assert len(val) == n_layer, (key, len(val))
        val = list(val) + [i in MTP_LOCAL_IDS for i in range(N_MTP)]
    elif vtype == gguf.GGUFValueType.ARRAY and isinstance(val, list) and len(val) == n_layer:
        # other per-layer arrays: each MTP depth takes the value of the first backbone layer of its kind (local/global)
        swa = list(r1.fields[f"{ARCH}.attention.sliding_window_pattern"].contents())
        first = {kind: next(j for j in range(n_layer) if bool(swa[j]) == kind) for kind in (True, False)}
        val = list(val) + [val[first[i in MTP_LOCAL_IDS]] for i in range(N_MTP)]
        print(f"extended per-layer array {key}: MTP values {val[n_layer:]}")
    sub = f.types[-1] if vtype == gguf.GGUFValueType.ARRAY else None
    w1.add_key_value(key, val, vtype, sub_type=sub)
w1.add_uint32(f"{ARCH}.nextn_predict_layers", N_MTP)
for t in r1.tensors:
    w1.add_tensor(t.name, np.array(t.data), raw_shape=list(reversed([int(x) for x in t.shape])), raw_dtype=t.tensor_type)
w1.write_header_to_file(); w1.write_kv_data_to_file(); w1.write_tensors_to_file(); w1.close()
print("shard 1 written:", DST(1), "tensors:", len(r1.tensors))

# ---- patch shard 2..3 split metadata in place (copies) ----
for n in (2, 3):
    r = GGUFReader(DST(n), "r+")
    for key, val in (("split.count", 4), ("split.tensors.count", n_total)):
        f = r.fields[key]
        f.parts[f.data[0]][0] = val
    r.data.flush() if hasattr(r.data, "flush") else None
    del r
    chk = GGUFReader(DST(n))
    print("patched", DST(n), int(chk.fields["split.count"].contents()), int(chk.fields["split.tensors.count"].contents()))

# ---- write shard 4: MTP tensors ----
w4 = GGUFWriter(DST(4), ARCH, use_temp_file=False)
w4.add_uint16("split.no", 3)
w4.add_uint16("split.count", 4)
w4.add_int32("split.tensors.count", n_total)
for name, arr, qt in mtp_tensors():
    arr = np.ascontiguousarray(arr, dtype=np.float32)
    if qt == QT.F32:
        w4.add_tensor(name, arr)
    else:
        q = gguf.quants.quantize(arr, qt)
        w4.add_tensor(name, q, raw_dtype=qt)
w4.write_header_to_file(); w4.write_kv_data_to_file(); w4.write_tensors_to_file(); w4.close()
print("shard 4 written:", DST(4), "MTP tensors:", n_mtp, "total tensors:", n_total)
