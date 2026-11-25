#!/usr/bin/env python3
"""analyse.py - determinism, the first divergent token, and the forced-prefix spec for the parity window.

Subcommands (all read the window's own output tree, one rows.jsonl a cell):

  report   --root OUT [--md FILE] [--json FILE]
           Every comparison the window needs: each arm against itself (two fresh boots), P against D at the same
           mode, and each lever against its own arm's control. Per (prompt, concurrency, j): text equality, the
           first divergent character, the first divergent token (reconstructed ids), and the two token texts.

  spec     --root OUT --pair A:B --c 1 --out SPEC.json
           The distribution spec: for every prompt where A and B differ at concurrency c, the chat prompt ids
           followed by A's reply ids up to the first divergent token (the forced prefix), and the two arms'
           divergent tokens (text and engine token hash) as the expectations.

  distsum  --root OUT [--md FILE]
           The temperature-1 sweeps: per cell and arm, the count of each drawn token and the gap estimate in
           nats between the two candidate tokens, ln((n1 + 0.5) / (n2 + 0.5)).
"""
from __future__ import annotations

import glob
import json
import math
import os
import sys


def load_cells(root: str) -> dict[tuple[str, int], dict]:
    """(label, C) -> {"prompt_ids": {prompt: ids}, "rows": {(prompt, j): row}}."""
    cells: dict[tuple[str, int], dict] = {}
    for path in sorted(glob.glob(os.path.join(root, "*", "c*", "rows.jsonl"))):
        label = path.split(os.sep)[-3]
        c = int(path.split(os.sep)[-2][1:])
        cell = cells.setdefault((label, c), {"prompt_ids": {}, "rows": {}})
        for line in open(path, encoding="utf-8"):
            if not line.strip():
                continue
            r = json.loads(line)
            if r.get("kind") == "prompt":
                if r.get("ids"):
                    cell["prompt_ids"][r["prompt"]] = r["ids"]
            elif r.get("kind") == "req":
                cell["rows"][(r["prompt"], r["j"])] = r
    return cells


def first_char_diff(a: str, b: str) -> int:
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return n


def first_tok_diff(a: list[int], b: list[int]) -> int:
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return n


def compare(ca: dict, cb: dict) -> list[dict]:
    out = []
    for key in sorted(set(ca["rows"]) & set(cb["rows"])):
        ra, rb = ca["rows"][key], cb["rows"][key]
        prompt, j = key
        a_ids, b_ids = ra.get("reply_ids") or [], rb.get("reply_ids") or []
        a_deltas, b_deltas = ra.get("deltas") or [], rb.get("deltas") or []
        k_ids = first_tok_diff(a_ids, b_ids)
        # the delta index is the engine's own token boundary when the stream carried one delta a token; the
        # reconstructed ids are the fallback, and both are recorded so a reader can see which one fired
        k_delta = first_tok_diff(a_deltas, b_deltas)
        one_to_one = (len(a_deltas) == ra.get("completion_tokens") and len(b_deltas) == rb.get("completion_tokens"))
        k = k_delta if one_to_one else k_ids
        out.append({
            "prompt": prompt, "j": j,
            "equal_text": ra["content"] == rb["content"],
            "equal_sha": ra["sha"] == rb["sha"],
            "equal_token_sha": ra.get("token_sha") == rb.get("token_sha"),
            "char": first_char_diff(ra["content"], rb["content"]),
            "token": k, "token_ids": k_ids, "token_delta": k_delta, "deltas_one_to_one": one_to_one,
            "a_len": len(a_ids), "b_len": len(b_ids),
            "a_completion_tokens": ra.get("completion_tokens"), "b_completion_tokens": rb.get("completion_tokens"),
            "a_prompt_tokens": ra.get("prompt_tokens"), "b_prompt_tokens": rb.get("prompt_tokens"),
            "a_token_text": (a_deltas[k] if k < len(a_deltas) else None),
            "b_token_text": (b_deltas[k] if k < len(b_deltas) else None),
            "a_token_sha": ra.get("token_sha"), "b_token_sha": rb.get("token_sha"),
            "ids_exact": (len(a_ids) == ra.get("completion_tokens")) and (len(b_ids) == rb.get("completion_tokens")),
            "a_ids_at": a_ids[k] if k < len(a_ids) else None,
            "b_ids_at": b_ids[k] if k < len(b_ids) else None,
            "prefix_chars": ra["content"][:first_char_diff(ra["content"], rb["content"])],
        })
    return out


def pairs(cells: dict) -> list[tuple[str, int, str, str]]:
    """(kind, C, a, b): the comparisons the report makes."""
    labels = {(lbl, c): None for (lbl, c) in cells}
    have = {lbl for (lbl, _c) in cells}
    out = []
    for c in sorted({c for (_l, c) in cells}):
        for arm, a, b in (("P", "P_a", "P_b"), ("D", "D_a", "D_b")):
            if a in have and b in have and (a, c) in cells and (b, c) in cells:
                out.append(("self", c, a, b))
        if (("P_a", c) in cells) and (("D_a", c) in cells):
            out.append(("cross", c, "P_a", "D_a"))
        if (("P_b", c) in cells) and (("D_b", c) in cells):
            out.append(("cross", c, "P_b", "D_b"))
        for lbl in sorted(have):
            if lbl in ("P_a", "D_a", "P_b", "D_b"):
                continue
            arm = lbl.split("_")[0]
            ctrl = f"{arm}_a"
            if (lbl, c) in cells and (ctrl, c) in cells:
                out.append(("lever", c, ctrl, lbl))
            other = "D_a" if arm == "P" else "P_a"
            if (lbl, c) in cells and (other, c) in cells:
                out.append(("lever-cross", c, other, lbl))
    return out


def cmd_report(root: str, md_path: str | None, json_path: str | None) -> None:
    cells = load_cells(root)
    lines = ["# Determinism and the first divergent token", "",
             "Per row: text equality, the first divergent character, the first divergent token (reconstructed ids),",
             "and the two token texts. `self` is one arm against itself on two fresh boots.", "",
             "| kind | C | A | B | rows | text equal | token_sha equal | first char | first token | A token | B token |",
             "|---|---:|---|---|---:|---:|---:|---:|---:|---|---|"]
    detail = []
    for kind, c, a, b in pairs(cells):
        rows = compare(cells[(a, c)], cells[(b, c)])
        for r in rows:
            r.update({"kind": kind, "C": c, "a": a, "b": b})
        detail.extend(rows)
        eq = sum(1 for r in rows if r["equal_text"])
        eqts = sum(1 for r in rows if r["equal_token_sha"])
        worst = min(rows, key=lambda r: (r["token"], r["char"])) if rows else None
        lines.append(f"| {kind} | {c} | {a} | {b} | {len(rows)} | {eq} | {eqts} | "
                     f"{worst['char'] if worst else '-'} | {worst['token'] if worst else '-'} | "
                     f"{(worst['a_token_text'] if worst else '-')!r} | {(worst['b_token_text'] if worst else '-')!r} |")
    for kind in ("self", "cross", "lever", "lever-cross"):
        sel = [r for r in detail if r["kind"] == kind]
        if not sel:
            continue
        lines += ["", f"## {kind}: one row a cell", "", "| C | A | B | prompt | j | equal | first token | A token (sha) | B token (sha) | a/b tokens |",
                  "|---:|---|---|---|---:|---|---:|---|---|---|"]
        for r in sel:
            lines.append(f"| {r['C']} | {r['a']} | {r['b']} | {r['prompt']} | {r['j']} | "
                         f"{'yes' if r['equal_text'] else 'no'} | {r['token']} | "
                         f"{r['a_token_text']!r} ({str(r['a_token_sha'])[:8]}) | "
                         f"{r['b_token_text']!r} ({str(r['b_token_sha'])[:8]}) | "
                         f"{r['a_completion_tokens']}/{r['b_completion_tokens']} |")
    lines += ["", "## Prompt ids the two arms render (the model's actual input)", "",
              "| C (pair) | prompt | A count | B count | ids equal |", "|---|---|---:|---:|---|"]
    for c in sorted({c for (_l, c) in cells}):
        for lbl_a, lbl_b in (("P_a", "D_a"), ("P_b", "D_b")):
            if (lbl_a, c) in cells and (lbl_b, c) in cells:
                ia, ib = cells[(lbl_a, c)]["prompt_ids"], cells[(lbl_b, c)]["prompt_ids"]
                for prompt in sorted(set(ia) | set(ib)):
                    lines.append(f"| {c} {lbl_a}/{lbl_b} | {prompt} | {len(ia.get(prompt, []))} | "
                                 f"{len(ib.get(prompt, []))} | {ia.get(prompt) == ib.get(prompt)} |")
    text = "\n".join(lines) + "\n"
    if md_path:
        os.makedirs(os.path.dirname(md_path), exist_ok=True)
        open(md_path, "w", encoding="utf-8").write(text)
    if json_path:
        os.makedirs(os.path.dirname(json_path), exist_ok=True)
        json.dump(detail, open(json_path, "w", encoding="utf-8"), indent=1)
    print(text)


def cmd_spec(root: str, pair: str, c: int, out_path: str) -> None:
    a, b = pair.split(":")
    cells = load_cells(root)
    ca, cb = cells[(a, c)], cells[(b, c)]
    rows = compare(ca, cb)
    spec = {"pair": pair, "c": c, "cells": []}
    for r in rows:
        if r["equal_text"]:
            continue
        prompt = r["prompt"]
        pids = ca["prompt_ids"].get(prompt)
        if not pids:
            print(f"SPEC skip {prompt} j{r['j']}: no prompt ids", flush=True)
            continue
        ra = ca["rows"][(prompt, r["j"])]
        if ra.get("prompt_tokens") != len(pids):
            print(f"SPEC skip {prompt} j{r['j']}: prompt_tokens {ra.get('prompt_tokens')} != /tokenize ids "
                  f"{len(pids)} (the forced prefix would not be the chat prompt)", flush=True)
            continue
        a_ids = ra.get("reply_ids") or []
        k = r["token"]
        if k > len(a_ids):
            print(f"SPEC skip {prompt} j{r['j']}: k {k} past {len(a_ids)} ids", flush=True)
            continue
        spec["cells"].append({
            "name": f"{prompt}-j{r['j']}",
            "prompt": prompt, "j": r["j"], "k": k,
            "prefix_ids": pids + a_ids[:k],
            "arms": {
                a.split("_")[0]: {"text": r["a_token_text"], "token_sha": r["a_token_sha"]},
                b.split("_")[0]: {"text": r["b_token_text"], "token_sha": r["b_token_sha"]},
            },
            "prompt_tokens": r["a_prompt_tokens"], "prefix_len": len(pids) + k,
            # a completions (token-id) prompt keeps no prompt-cache state, so every sample pays its prefill: the
            # 8k cell gets 24 samples at T=1; the 1k cells 60 at each of three temperatures (the low one turns a
            # fraction of a logit into a large split, so it reads the margin that decides a greedy argmax)
            "seeds": 24 if "8k" in prompt else 60,
            "temperatures": [1.0] if "8k" in prompt else [1.0, 0.2, 0.05, 0.01],
        })
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    json.dump(spec, open(out_path, "w", encoding="utf-8"), indent=1)
    for cell in spec["cells"]:
        print(f"SPEC {cell['name']} k {cell['k']} prefix {cell['prefix_len']} "
              f"A {cell['arms'][a.split('_')[0]]['text']!r} B {cell['arms'][b.split('_')[0]]['text']!r}", flush=True)


def cmd_distsum(root: str, md_path: str | None) -> None:
    by_cell: dict[tuple[str, str, str], dict[str, int]] = {}
    per_seed: dict[tuple[str, str, str], dict[int, str]] = {}
    controls: dict[tuple[str, str], dict] = {}
    texts: dict[str, str] = {}
    for path in sorted(glob.glob(os.path.join(root, "dist", "*.jsonl"))):
        for line in open(path, encoding="utf-8"):
            if not line.strip():
                continue
            r = json.loads(line)
            key = (r["cell"], r["arm"])
            if r["kind"] == "control":
                controls[key] = r
            else:
                sha = r.get("token_sha") or ("text:" + (r.get("text") or ""))
                tkey = (r["cell"], r["arm"], str(r.get("temperature", "")))
                by_cell.setdefault(tkey, {})
                by_cell[tkey][sha] = by_cell[tkey].get(sha, 0) + 1
                per_seed.setdefault((r["cell"], str(r.get("temperature", "")), r["arm"]), {})[r["seed"]] = sha
                texts[sha] = r.get("text") or ""
    lines = ["# The candidate distribution at the first divergent token, by temperature", "",
             "The control is a temperature-0, one-token request at the same forced prefix: it must reproduce the",
             "arm's own next token from the greedy cell. `n(P)/n(D)` counts the two arms' divergent tokens in this",
             "arm's samples; `gap` is ln((n(P) + 0.5)/(n(D) + 0.5)) in nats at that temperature, positive for P's",
             "token; `logit gap` is gap x T, the same quantity in logits (a bf16 step near a logit of 10 is 0.0625).",
             "", "| cell | arm | T | control | control ok | samples | top counts | n(P)/n(D) | gap ln(P/D) | logit gap |",
             "|---|---|---:|---|---:|---:|---|---:|---:|---:|"]
    for (cell, arm, temp) in sorted(by_cell):
        counts = by_cell[(cell, arm, temp)]
        ctrl = controls.get((cell, arm), {})
        top = sorted(counts.items(), key=lambda kv: -kv[1])
        shown = ", ".join(f"{(texts.get(s) or str(s)[:8])!r}:{n}" for s, n in top[:4])
        arms = ctrl.get("cands") or {}
        gap = None
        counts_shown = ""
        if set(arms) >= {"P", "D"}:
            np_ = counts.get(arms["P"].get("token_sha"), 0)
            nd = counts.get(arms["D"].get("token_sha"), 0)
            gap = math.log((np_ + 0.5) / (nd + 0.5))
            counts_shown = f"{np_}/{nd}"
        t = float(temp) if temp else 1.0
        # the keyed draw is bit-identical on both arms (sampling.zig keyBits), so the same seed is the same
        # experiment twice: the disagreement rate is a paired measure of how far the arms' distributions are apart
        sp = per_seed.get((cell, temp, "P"), {})
        sd = per_seed.get((cell, temp, "D"), {})
        seeds = sorted(set(sp) & set(sd))
        pair = (f"{sum(1 for k in seeds if sp[k] != sd[k])}/{len(seeds)}" if seeds else "-")
        lines.append(f"| {cell} | {arm} | {temp} | {ctrl.get('text')!r} | {ctrl.get('control_ok')} | "
                     f"{sum(counts.values())} | {shown} | {counts_shown} | "
                     f"{('%.2f' % gap) if gap is not None else '-'} | "
                     f"{('%.3f' % (gap * t)) if gap is not None else '-'} | {pair} |")
    text = "\n".join(lines) + "\n"
    if md_path:
        os.makedirs(os.path.dirname(md_path), exist_ok=True)
        open(md_path, "w", encoding="utf-8").write(text)
    print(text)


def main() -> None:
    cmd = sys.argv[1]
    args = sys.argv[2:]
    def opt(name: str, default: str | None = None) -> str | None:
        return args[args.index(name) + 1] if name in args else default
    root = opt("--root")
    assert root
    if cmd == "report":
        cmd_report(root, opt("--md"), opt("--json"))
    elif cmd == "spec":
        cmd_spec(root, opt("--pair"), int(opt("--c", "1")), opt("--out"))
    elif cmd == "distsum":
        cmd_distsum(root, opt("--md"))
    else:
        raise SystemExit(f"unknown subcommand {cmd}")


if __name__ == "__main__":
    main()
