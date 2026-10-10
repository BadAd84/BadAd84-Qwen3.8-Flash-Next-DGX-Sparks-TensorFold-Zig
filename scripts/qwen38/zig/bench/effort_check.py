#!/usr/bin/env python3
"""effort_check.py <port> [extra-body JSON]: does the live server honour RigMark's extra body? (zab_rm.sh runs it
before RigMark; default body {"reasoning_effort": "low"}, rigmark_run.sh's.) The engine is the serving container's
(rigmark_meta.engine_of: Zig `tensorfold-native serve` or Python `tensorfold serve`).

Zig server:
1. /tokenize (the tokenizer and chat template only, no generation) renders one user message with the body merged in
   and without it: the body must render the chat template's low-effort instruction ("Reasoning effort is set to
   low") and the bare request must not.
2. One greedy chat request with the body (max_tokens 8, not streamed): its `tensorfold` block must report
   enable_thinking true and reasoning_effort "low".
Python server (TensorFold v0.6.1's cuda/http.py: no /tokenize route, and its `tensorfold` block is the engine's
stats, no enable_thinking / reasoning_effort):
1. The server's own request preparation, in the serving container (docker exec, CPU only, the container's own code,
   checkpoint and serve flags): tensorfold.cuda.App built as cli.py builds it (default thinking from --thinking /
   --no-thinking, --reasoning-effort, --thinking-budget) around a stand-in engine, then App._prepare(body, chat) for
   the message with the body and without it: the body must render the low-effort instruction with thinking on, the
   bare request must not.
2. One greedy chat request with the body (max_tokens 8, not streamed): its usage.prompt_tokens must equal the token
   count step 1 prepared for the body (so the live server rendered that same prompt; step 1's two prompts must differ
   in length, else that count could not tell them apart), and it must think
   (usage.completion_tokens_details.reasoning_tokens > 0).
Prints "effort <body>: ..." (the counts and what was rendered) and "effort OK" or "effort FAILED: <why>"; exit 0 / 1."""
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rigmark_meta  # noqa: E402  (beside this script: the serving container and its engine, one implementation)

LOW = "Reasoning effort is set to low"
MESSAGES = [{"role": "user", "content": "Write a haiku."}]
# Run inside the Python serving container: its App, constructed as tensorfold/cli.py does, prepares each body exactly
# as a live chat request is prepared (App._prepare: thinking_fields, heard_effort, the template, the tokenizer).
PROBE = r"""
import json, sys
from pathlib import Path
from tensorfold.cuda.server import App
class Stand:                      # App reads only these from an engine while it prepares a request
    eos, vision, supports_logprobs = (), None, False
model_dir, thinking, effort, budget, bodies = Path(sys.argv[1]), sys.argv[2] == "1", sys.argv[3] or None, int(sys.argv[4]), json.loads(sys.argv[5])
app = App(Stand(), model_dir, "probe", default_thinking=thinking, reasoning_effort=effort, thinking_budget=budget)
out = []
for body in bodies:
    p = app._prepare(body, True)
    out.append({"tokens": len(p.prompt), "thinking": p.thinking, "text": app.tok.decode(p.prompt, skip_special_tokens=False)})
print(json.dumps(out))
"""


def post(port: int, path: str, body: dict) -> dict:
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return json.load(r)


def rendered(port: int, extra: dict) -> tuple[int, str]:
    out = post(port, "/tokenize", {"messages": MESSAGES, "return_token_strs": True, **extra})
    text = "".join(out.get("token_strs") or []).replace("\u0120", " ").replace("\u010a", "\n")
    return int(out["count"]), text


def zig(port: int, raw: str, extra: dict) -> list[str]:
    n_with, t_with = rendered(port, extra)
    n_bare, t_bare = rendered(port, {})
    reply = post(port, "/v1/chat/completions", {"messages": MESSAGES, "max_tokens": 8, "temperature": 0,
                                                "stream": False, **extra})
    rt = reply.get("tensorfold") or {}
    on, effort = rt.get("enable_thinking"), rt.get("reasoning_effort")
    print(f"effort {raw}: tokenize {n_with} vs {n_bare} tokens, low instruction "
          f"{'rendered' if LOW in t_with else 'NOT rendered'}; reply enable_thinking {on} reasoning_effort {effort}")
    why = []
    if LOW not in t_with:
        why.append("the body does not render the low-effort instruction")
    if LOW in t_bare:
        why.append("the bare request renders it too (the check cannot tell the body apart)")
    if on is not True or effort != "low":
        why.append(f"the reply ran enable_thinking {on} reasoning_effort {effort}")
    return why


def last_flag(args: list[str], on: str, off: str, default: bool) -> bool:
    """argparse's BooleanOptionalAction: the last of --x / --no-x wins."""

    seen = [a for a in args if a in (on, off)]
    return default if not seen else seen[-1] == on


def python(port: int, raw: str, extra: dict) -> list[str]:
    c = rigmark_meta.serving_container(port)
    args = list(c.get("Args") or [])
    opt = dict(zip(args, args[1:]))
    name, rev = rigmark_meta.model_of(c, args)
    model_dir = f"/root/.cache/huggingface/hub/models--{name.replace('/', '--')}/snapshots/{rev}"
    thinking = last_flag(args, "--thinking", "--no-thinking", True)          # tensorfold/cli_args.py: default True
    bodies = [{"messages": MESSAGES, **extra}, {"messages": MESSAGES}]
    probe = subprocess.run(["docker", "exec", c["Id"], "python", "-c", PROBE, model_dir, "1" if thinking else "0",
                            opt.get("--reasoning-effort", ""), opt.get("--thinking-budget", "0"), json.dumps(bodies)],
                           capture_output=True, text=True, timeout=300)
    if probe.returncode != 0:
        return [f"the in-container probe failed (exit {probe.returncode}): {probe.stderr.strip()[-300:]}"]
    (p_with, p_bare) = json.loads(probe.stdout.strip().splitlines()[-1])
    reply = post(port, "/v1/chat/completions", {"messages": MESSAGES, "max_tokens": 8, "temperature": 0,
                                                "stream": False, **extra})
    usage = reply.get("usage") or {}
    live = usage.get("prompt_tokens")
    thought = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens")
    print(f"effort {raw}: App._prepare in the serving container {p_with['tokens']} vs {p_bare['tokens']} tokens, low "
          f"instruction {'rendered' if LOW in p_with['text'] else 'NOT rendered'}, thinking {p_with['thinking']}; "
          f"live reply prompt_tokens {live}, reasoning_tokens {thought}")
    why = []
    if LOW not in p_with["text"] or p_with["thinking"] is not True:
        why.append(f"the body does not prepare a thinking prompt at effort low (thinking {p_with['thinking']})")
    if LOW in p_bare["text"]:
        why.append("the bare request renders it too (the check cannot tell the body apart)")
    if p_with["tokens"] == p_bare["tokens"]:
        why.append("the body and the bare request prepare prompts of one length (the live count cannot tell them apart)")
    if live != p_with["tokens"]:
        why.append(f"the live reply's prompt has {live} tokens, the prepared body {p_with['tokens']}")
    if not thought:
        why.append(f"the live reply did not think (reasoning_tokens {thought})")
    return why


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    port = int(sys.argv[1])
    raw = sys.argv[2] if len(sys.argv) > 2 else '{"reasoning_effort": "low"}'
    extra = json.loads(raw)
    try:
        engine = rigmark_meta.engine_of(list(rigmark_meta.serving_container(port).get("Args") or []))
        why = python(port, raw, extra) if engine == "python" else zig(port, raw, extra)
    except (Exception, SystemExit) as exc:  # noqa: BLE001  (any failure to ask is a failed check)
        print(f"effort FAILED: {type(exc).__name__}: {exc}")
        return 1
    print("effort OK" if not why else "effort FAILED: " + "; ".join(why))
    return 1 if why else 0


if __name__ == "__main__":
    sys.exit(main())
