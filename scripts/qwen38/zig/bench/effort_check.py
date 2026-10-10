#!/usr/bin/env python3
"""effort_check.py <port> [extra-body JSON]: does the live Zig server honour RigMark's extra body? (zab_rm.sh runs it
before RigMark; default body {"reasoning_effort": "low"}, rigmark_run.sh's.)

1. /tokenize (the tokenizer and chat template only, no generation) renders one user message with the body merged in
   and without it: the body must render the chat template's low-effort instruction ("Reasoning effort is set to
   low") and the bare request must not.
2. One greedy chat request with the body (max_tokens 8, not streamed): its `tensorfold` block must report
   enable_thinking true and reasoning_effort "low".
Prints "effort <body>: tokenize <n> vs <n> tokens, low instruction rendered|NOT rendered; reply enable_thinking <b>
reasoning_effort <e>" and "effort OK" or "effort FAILED: <why>"; exit 0 / 1."""
import json
import sys
import urllib.request

LOW = "Reasoning effort is set to low"


def post(port: int, path: str, body: dict) -> dict:
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def rendered(port: int, extra: dict) -> tuple[int, str]:
    out = post(port, "/tokenize", {"messages": [{"role": "user", "content": "Write a haiku."}],
                                   "return_token_strs": True, **extra})
    text = "".join(out.get("token_strs") or []).replace("\u0120", " ").replace("\u010a", "\n")
    return int(out["count"]), text


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    port = int(sys.argv[1])
    raw = sys.argv[2] if len(sys.argv) > 2 else '{"reasoning_effort": "low"}'
    extra = json.loads(raw)
    why = []
    try:
        n_with, t_with = rendered(port, extra)
        n_bare, t_bare = rendered(port, {})
        reply = post(port, "/v1/chat/completions", {"messages": [{"role": "user", "content": "Write a haiku."}],
                                                    "max_tokens": 8, "temperature": 0, "stream": False, **extra})
    except Exception as exc:  # noqa: BLE001  (any failure to ask is a failed check)
        print(f"effort FAILED: {type(exc).__name__}: {exc}")
        return 1
    rt = reply.get("tensorfold") or {}
    on, effort = rt.get("enable_thinking"), rt.get("reasoning_effort")
    print(f"effort {raw}: tokenize {n_with} vs {n_bare} tokens, low instruction "
          f"{'rendered' if LOW in t_with else 'NOT rendered'}; reply enable_thinking {on} reasoning_effort {effort}")
    if LOW not in t_with:
        why.append("the body does not render the low-effort instruction")
    if LOW in t_bare:
        why.append("the bare request renders it too (the check cannot tell the body apart)")
    if on is not True or effort != "low":
        why.append(f"the reply ran enable_thinking {on} reasoning_effort {effort}")
    print("effort OK" if not why else "effort FAILED: " + "; ".join(why))
    return 1 if why else 0


if __name__ == "__main__":
    sys.exit(main())
