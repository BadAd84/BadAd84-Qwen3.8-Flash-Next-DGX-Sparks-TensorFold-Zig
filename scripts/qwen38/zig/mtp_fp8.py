#!/usr/bin/env python3
"""mtp_fp8.py OUTDIR: the INT4-AutoRound checkpoint's MTP-layer bf16 linears (attention q/k/v/o, the hyper-connection
down/up of both blocks and the mixer) on block FP8, as TF_FLASHNEXT_MTP_FP8's overlay: e4m3 codes `.weight` and fp32
`.weight_scale_inv` per 128x128 block (scale = block amax / 448, weight ~= codes * scale; the checkpoint's own
block-FP8 convention). Drafts only: the MTP head proposes, the target model's verify keeps or rejects every token.
Runs in the image (torch, safetensors) with the HF cache mounted writable at /hf."""
import glob, json, os, sys
import torch
from safetensors import safe_open
from safetensors.torch import save_file

snap = glob.glob("/hf/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/*")[0]
idx = json.load(open(os.path.join(snap, "model.safetensors.index.json")))["weight_map"]
names = [f"mtp.layers.0.self_attn.{p}_proj" for p in "qkvo"]
names += [f"mtp.layers.0.{b}_hyper_connection.input_mix_weight_{d}" for b in ("attn", "mlp") for d in ("down", "up")]
names += [f"mtp.hyper_connection_mixer.input_mix_weight_{d}" for d in ("down", "up")]
out = {}
for n in names:
    key = n + ".weight"
    with safe_open(os.path.join(snap, idx[key]), "pt") as f:
        w = f.get_tensor(key)
    assert w.dtype == torch.bfloat16 and w.dim() == 2, (key, w.dtype, w.shape)
    rows, cols = w.shape
    rb, cb = (rows + 127) // 128, (cols + 127) // 128
    pad = torch.zeros(rb * 128, cb * 128, dtype=torch.float32)
    pad[:rows, :cols] = w.float()
    blocks = pad.view(rb, 128, cb, 128)
    amax = blocks.abs().amax(dim=(1, 3))
    scale = torch.where(amax > 0, amax / 448.0, torch.ones_like(amax))
    q = (blocks / scale[:, None, :, None]).clamp(-448, 448).to(torch.float8_e4m3fn)
    codes = q.view(rb * 128, cb * 128)[:rows, :cols].contiguous()
    err = (codes.float().view(rows, cols) - 0).numel()
    deq = (q.float() * scale[:, None, :, None]).view(rb * 128, cb * 128)[:rows, :cols]
    rel = ((deq - w.float()).norm() / w.float().norm()).item()
    print(f"{key} {tuple(w.shape)} blocks {rb}x{cb} rel err {rel:.4f}")
    out[key] = codes
    out[n + ".weight_scale_inv"] = scale.contiguous()
os.makedirs(sys.argv[1], exist_ok=True)
save_file(out, os.path.join(sys.argv[1], "mtp-fp8.safetensors"))
print("wrote", sys.argv[1], len(out), "tensors")
