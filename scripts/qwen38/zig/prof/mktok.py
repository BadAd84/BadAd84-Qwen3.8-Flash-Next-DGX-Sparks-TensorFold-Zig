#!/usr/bin/env python3
"""mktok.py OUT TOKENS SEED: a chat-framed prose prompt (qf_harness.prose) as comma-separated token ids for
`tensorfold bench --tokens-file`. Runs in the image (tokenizers) with ~/work and the HF cache mounted."""
import sys, glob
sys.path.insert(0, "/w")
import qf_harness as H
from tokenizers import Tokenizer
snap = glob.glob("/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/*")[0]
tok = Tokenizer.from_file(snap + "/tokenizer.json")
out, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
body = tok.encode(H.prose(n, seed), add_special_tokens=False).ids
ids = [248045, 846, 198] + body + [248046, 198, 248045, 74455, 198, 248068, 271, 248069, 271]
open(out, "w").write(",".join(map(str, ids)))
print(out, len(ids))
