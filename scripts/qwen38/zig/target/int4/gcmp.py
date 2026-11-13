"""gcmp.py REF.json OURS.json [TOKENIZER.json] - golden replies compared prompt by prompt: identical, or the first
divergent token (tokenized with the checkpoint's own tokenizer when given, else the first differing character)."""
import json
import sys

ref = json.load(open(sys.argv[1]))
ours = json.load(open(sys.argv[2]))
tok = None
if len(sys.argv) > 3:
    try:
        from tokenizers import Tokenizer

        tok = Tokenizer.from_file(sys.argv[3])
    except Exception as e:  # noqa: BLE001 - report and fall back to characters
        print(f"no tokenizer ({e}); characters only")
same = 0
for r, o in zip(ref, ours):
    a, b = r.get("content") or "", o.get("content") or ""
    if a == b and r.get("token_sha") == o.get("token_sha"):
        same += 1
        print(f"{r['id']}: identical ({r.get('completion_tokens')} tokens, token_sha {r.get('token_sha')})")
        continue
    c = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    where = f"char {c}"
    if tok is not None:
        ta, tb = tok.encode(a, add_special_tokens=False).ids, tok.encode(b, add_special_tokens=False).ids
        t = next((i for i, (x, y) in enumerate(zip(ta, tb)) if x != y), min(len(ta), len(tb)))
        where = f"token {t} of {len(ta)} / {len(tb)}"
    print(f"{r['id']}: differs at {where}; ref ...{a[max(0, c - 40):c + 40]!r}")
    print(f"{' ' * len(r['id'])}  ours ...{b[max(0, c - 40):c + 40]!r}")
print(f"identical {same} of {len(ref)}")
