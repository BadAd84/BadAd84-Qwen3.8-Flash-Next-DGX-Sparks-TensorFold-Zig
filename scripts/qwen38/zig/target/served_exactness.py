"""Drafted against "draft": false and resumed against fresh, over HTTP on a TensorFold server; standard library only.

  served_exactness.py drafts URL MODEL PROMPTS.json OUT.json [--tokens N]  each prompt with "draft": false, then drafted
  served_exactness.py turns URL MODEL TURNS.json OUT.json [--tokens N]     a prompt, then the same chat extended a turn
  served_exactness.py fresh URL MODEL TURNS_OUT.json OUT.json              the extended chats on a server that keeps no
                                                                           prompts (--prompt-cache-gib 0), each compared
                                                                           with the resumed reply turns recorded

PROMPTS.json is a list of {"name", "kind": "chat" | "completion", "prompt"}; TURNS.json a list of {"name", "prompt",
"follow"}, where a null follow sends the first request again. Requests are greedy (temperature 0, seed 1234), thinking
off, with return_token_ids (dropped if the server answers HTTP 400 to it); drafts also sends ignore_eos, so each reply
runs to N tokens. Replies are compared by their token ids (tensorfold.token_ids), else tensorfold.token_sha256, else
text, and the basis is recorded. A failed request, an unequal pair, a fresh request that reports cached prompt tokens
or a resumed request that reports none exits 1.
"""

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request

SEED = 1234
FIELDS = ("draft", "text", "finish_reason", "prompt_tokens", "completion_tokens", "cached_tokens", "token_ids",
          "token_sha256", "rounds", "drafted", "accepted")


def post(url: str, body: dict) -> dict:
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=1800) as reply:
        return json.load(reply)


def failed(exc: Exception) -> dict:
    return {**{k: None for k in FIELDS}, "text": "", "error": f"{type(exc).__name__}: {exc}"}


def ask(base: str, model: str, kind: str, content, tokens: int, draft: bool, ignore_eos: bool) -> dict:
    body = {"model": model, "max_tokens": tokens, "temperature": 0, "seed": SEED, "return_token_ids": True}
    if ignore_eos:
        body["ignore_eos"] = True
    if not draft:
        body["draft"] = False
    if kind == "completion":
        url = base + "/v1/completions"
        body["prompt"] = content
    else:
        url = base + "/v1/chat/completions"
        body["messages"] = content if isinstance(content, list) else [{"role": "user", "content": content}]
        body["chat_template_kwargs"] = {"enable_thinking": False}
    try:
        try:
            doc = post(url, body)
        except urllib.error.HTTPError as exc:
            if exc.code != 400:
                raise
            del body["return_token_ids"]
            doc = post(url, body)
    except Exception as exc:  # noqa: BLE001 - a failed request is recorded and fails its comparison
        return failed(exc)
    choice = doc["choices"][0]
    text = choice.get("text") if kind == "completion" else (choice.get("message") or {}).get("content")
    usage = doc.get("usage") or {}
    runtime = doc.get("tensorfold") or {}
    spec = doc.get("speculative") or runtime.get("speculative") or {}
    ids = runtime.get("token_ids")
    return {"draft": draft, "text": text or "", "finish_reason": choice.get("finish_reason"),
            "prompt_tokens": usage.get("prompt_tokens"), "completion_tokens": usage.get("completion_tokens"),
            "cached_tokens": (usage.get("prompt_tokens_details") or {}).get("cached_tokens"),
            "token_ids": ids if isinstance(ids, list) else None, "token_sha256": runtime.get("token_sha256"),
            "rounds": spec.get("rounds"), "drafted": spec.get("drafted"), "accepted": spec.get("accepted")}


def same(a: dict, b: dict) -> dict:
    """Equality of two replies on the strongest basis both carry; a failed request is never equal."""
    if a.get("error") or b.get("error"):
        basis, equal = "error", False
    elif a["token_ids"] is not None and b["token_ids"] is not None:
        basis, equal = "token_ids", a["token_ids"] == b["token_ids"]
    elif a["token_sha256"] and b["token_sha256"]:
        basis, equal = "token_sha256", a["token_sha256"] == b["token_sha256"]
    else:
        basis, equal = "text", a["text"] == b["text"]
    return {"basis": basis, "equal": equal, "text_equal": a["text"] == b["text"],
            "tokens": [a["completion_tokens"], b["completion_tokens"]]}


def ids_sha(reply: dict) -> str | None:
    ids = reply["token_ids"]
    return hashlib.sha256(json.dumps(ids).encode()).hexdigest()[:16] if ids is not None else None


def drafts(args) -> int:
    rows, bad = [], 0
    for item in json.load(open(args.inp, encoding="utf-8")):
        plain = ask(args.base, args.model, item["kind"], item["prompt"], args.tokens, False, True)
        drafted = ask(args.base, args.model, item["kind"], item["prompt"], args.tokens, True, True)
        cmp = same(drafted, plain)
        bad += not cmp["equal"]
        rows.append({"name": item["name"], "plain": plain, "drafted": drafted, **cmp})
        print(f'{"ok  " if cmp["equal"] else "FAIL"} drafted == "draft": false  {item["name"]}: {cmp["basis"]}, '
              f'{drafted["completion_tokens"]} tokens, ids {ids_sha(drafted)}, accepted {drafted["accepted"]} of '
              f'{drafted["drafted"]} drafted (plain: {plain["drafted"]}) {plain.get("error") or drafted.get("error") or ""}',
              flush=True)
    json.dump({"tokens": args.tokens, "rows": rows}, open(args.out, "w", encoding="utf-8"), indent=1)
    return 1 if bad else 0


def turns(args) -> int:
    rows = []
    for item in json.load(open(args.inp, encoding="utf-8")):
        first = ask(args.base, args.model, "chat", item["prompt"], args.tokens, True, False)
        chat = [{"role": "user", "content": item["prompt"]}]
        if item.get("follow") is not None:
            chat += [{"role": "assistant", "content": first["text"]}, {"role": "user", "content": item["follow"]}]
        resumed = ask(args.base, args.model, "chat", chat, args.tokens, True, False) if not first.get("error") else first
        rows.append({"name": item["name"], "turn": chat, "first": first, "resumed": resumed})
        print(f'turn {item["name"]}: prompt {resumed["prompt_tokens"]} tokens, cached {resumed["cached_tokens"]}, '
              f'reply {resumed["completion_tokens"]} tokens, ids {ids_sha(resumed)} {resumed.get("error") or ""}', flush=True)
    json.dump({"tokens": args.tokens, "rows": rows}, open(args.out, "w", encoding="utf-8"), indent=1)
    return 0 if all((r["resumed"]["cached_tokens"] or 0) > 0 and not r["resumed"].get("error") for r in rows) else 1


def fresh(args) -> int:
    recorded = json.load(open(args.inp, encoding="utf-8"))
    rows, bad = [], 0
    for row in recorded["rows"]:
        resumed = row["resumed"]
        plain = ask(args.base, args.model, "chat", row["turn"], recorded["tokens"], False, False)
        drafted = ask(args.base, args.model, "chat", row["turn"], recorded["tokens"], True, False)
        out = {"name": row["name"], "resumed_cached": resumed["cached_tokens"], "fresh_plain": plain,
               "fresh_drafted": drafted, "plain": same(resumed, plain), "drafted": same(resumed, drafted)}
        problems = [f"request failed: {side['error']}" for side in (resumed, plain, drafted) if side.get("error")]
        if not (resumed["cached_tokens"] or 0) > 0:
            problems.append(f'the resumed request reported {resumed["cached_tokens"]} cached tokens (not a resume)')
        for side in (plain, drafted):
            if side["cached_tokens"] != 0:
                problems.append(f'a fresh request reported {side["cached_tokens"]} cached tokens (not fresh)')
        for key in ("plain", "drafted"):
            if not out[key]["equal"]:
                problems.append(f'resumed != fresh ({key}) by {out[key]["basis"]}')
        out["problems"] = problems
        bad += bool(problems)
        rows.append(out)
        print(f'{"FAIL" if problems else "ok  "} resumed == fresh  {row["name"]}: resumed from {resumed["cached_tokens"]} '
              f'of {resumed["prompt_tokens"]} prompt tokens; fresh cached {plain["cached_tokens"]} and '
              f'{drafted["cached_tokens"]}; {out["plain"]["basis"]}, {resumed["completion_tokens"]} tokens, '
              f'ids {ids_sha(resumed)} / {ids_sha(plain)} / {ids_sha(drafted)} {"; ".join(problems)}', flush=True)
    json.dump({"tokens": recorded["tokens"], "rows": rows}, open(args.out, "w", encoding="utf-8"), indent=1)
    return 1 if bad else 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=("drafts", "turns", "fresh"))
    p.add_argument("base")
    p.add_argument("model")
    p.add_argument("inp")
    p.add_argument("out")
    p.add_argument("--tokens", type=int, default=256)
    args = p.parse_args()
    args.base = args.base.rstrip("/")
    return {"drafts": drafts, "turns": turns, "fresh": fresh}[args.mode](args)


if __name__ == "__main__":
    sys.exit(main())
