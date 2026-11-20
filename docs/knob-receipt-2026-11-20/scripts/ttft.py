#!/usr/bin/env python3
"""ttft.py <port> [options]: client-measured time to first token (TTFT) against the recipe's Zig server
(tensorfold-native serve, spark6), the owner's "how fast the model feels".

TTFT = the time from sending the request to the first streamed CONTENT, REASONING or TOOL-CALL token. The Zig server's
OpenAI stream (src/server/openai.zig, sse.zig; measured on spark6's zmerge5 serve 2026-10-10, zab_rm.sh's SHAPE
lines) writes its 200 and headers after rendering and tokenizing the prompt (`chat.prepare`, before the engine sees
the request), then at once a role chunk (`delta: {"role": "assistant"}`), then one `data:` chunk per delta
(`content`, or `reasoning_content` while the model thinks; often several tokens a chunk), then a last chunk with
`delta: {}`, the finish reason, `exact_mode`, `tensorfold` (the runtime block: `enable_thinking`, `reasoning_effort`
(null = the template's default), `prefill_seconds`, `time_to_first_token`, `token_sha`, ...), `speculative` and
`usage` (`prompt_tokens_details.cached_tokens`; in a chunk of its own with `choices: []` when the request sets
`stream_options.include_usage`), then `data: [DONE]`. It sends no keep-alive comments. None of the role chunk, an
empty delta, an SSE comment or an Anthropic `ping` / `message_start` / empty `content_block_start` counts as a token
(the parser follows the SSE rules either way).

Cases (each repeated --reps times, interleaved rep by rep; medians and p90 at the end):
- cold<N>-<off|on>: a prompt of ~N tokens (1k / 8k / 32k / 120k by default; a numbered filler at its measured ~21.8
  Qwen3.8 tokens a line) whose first line is a fresh UUID salt, so nothing of it is cached; thinking off and on
  (`chat_template_kwargs.enable_thinking`, which the server reads first; thinking on runs at the template's default
  effort, xhigh);
- warm<A>: an agent turn: a kept ~100k conversation (its first user message and the reply to it), then ~A new tokens
  (2k) behind a fresh salt. The conversation's first request (the previous turn) is sent again, unmeasured, right
  before every warm sample, so the server holds its state as it would right after an agent's previous turn; the Zig
  prompt cache keeps states in GPU memory and a run's cold 120k prompts can evict an older one.
Loads (--loads): idle, and load3 = the same while 3 other streams decode (a background generator in this script:
3 streaming replies on their own ~3k prompts, restarted when one ends; every measured request waits until all 3 are
decoding before it is sent).

Per sample the TTFT splits into
  admit   = the response headers (client-measured: send + render/tokenize; the Zig server answers 200 after
            `chat.prepare`, before the engine admits the request),
  queue   = the server's queue wait, IF the reply's `tensorfold` block carries one (queue_s / queued_s / queue_wait_s
            / wait_s; the Zig server reports none, so it is `-` and stays inside `other`),
  prefill = the server's `tensorfold.prefill_seconds` (from the engine's submit to the prompt pass's end, its first
            token included: on spark6 it is all but ~0.01 s of ttft - admit; the OpenAI route's last chunk carries it,
            the Anthropic route does not: `-`),
  other   = ttft - admit - queue - prefill: what is left (scheduling between the steps and the emit);
and, beside the split, server = the server's own `tensorfold.time_to_first_token` (from the request's arrival).
Output (stdout), one line per sample, then one summary line per case and load:
  sample <case> <load> ttft <s> admit <s> queue <s|-> prefill <s|-> other <s|-> server <s|-> prompt <n> cached <n>
         first <content|reasoning|tool> others <n>[ NOTCOLD| NOTWARM| NOLOAD ...]
  error <case|load> <load> rep <i>: <message>
  summary <case> <load> n <n> ttft med <s> p90 <s> admit <s> queue <s> prefill <s> other <s> server <s> excluded <n>
A flagged sample (a cold prompt that hit the cache, a warm turn that missed it, a load sample sent while fewer than
the asked streams decoded) is printed but left out of the medians. Exit 1 on any error.

  ttft.py report FILE...   the TTFT section of harness logs whose sample lines carry a `TTFT <arm> ` prefix: per case
                           and load, each arm's median / p90 and its change against the first arm; the split medians.
zab_rm_sum.py imports collect() / section() from here.
Offline test: tests/test_ttft.py (a fake server streaming the Zig shape); mutants: tests/mutants_ttft.py.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import re
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter, defaultdict

WORDS = ("lattice probe ferrule datum spindle gauge trellis offset stylus kinematic fixture wafer cosine baseline "
         "granite bearing encoder servo axis spline tolerance flatness runout").split()
ASK = "\n\nContinue the numbered list above from where it stops, in the same format."
QUEUE_KEYS = ("queue_s", "queued_s", "queue_wait_s", "wait_s")
PREFILL_KEY = "prefill_seconds"                 # the Zig server's runtime block (chat.zig)
SERVER_TTFT_KEY = "time_to_first_token"
LINE_TOKENS = 21.8          # Qwen3.8 Flash Next tokens a filler line (its tokenizer.json: 21.70-21.88 over 3 seeds,
                            # 400 and 5,000 lines; 5,000 lines = 108.9k-109.2k tokens)


def filler(tokens: int, rnd: random.Random) -> str:
    """A numbered filler of ~<tokens> Qwen3.8 tokens."""
    return "\n".join(f"{i:06d} " + " ".join(rnd.choice(WORDS) for _ in range(11))
                     for i in range(max(1, round(tokens / LINE_TOKENS))))


def tokens_of(label: str) -> int:
    label = label.strip().lower()
    return int(float(label[:-1]) * 1000) if label.endswith("k") else int(label)


def request_body(api: str, messages: list[dict], max_tokens: int, thinking: bool, model: str) -> dict:
    if api == "anthropic":
        return {"model": model, "max_tokens": max_tokens, "temperature": 0, "stream": True, "messages": messages,
                "thinking": {"type": "adaptive"} if thinking else {"type": "disabled"}}
    return {"model": model, "max_tokens": max_tokens, "temperature": 0, "stream": True, "messages": messages,
            "chat_template_kwargs": {"enable_thinking": thinking}}


class Sse:
    """The SSE format's rules: a blank line dispatches an event, `:` starts a comment, `data:` lines join with \\n,
    a line ends in \\n or \\r\\n. feed() returns (event name, data, time of the event's first data line) or None."""

    def __init__(self) -> None:
        self.name, self.data, self.t = "", [], None

    def feed(self, raw: bytes, t: float):
        line = raw.decode("utf-8", "replace").rstrip("\n").rstrip("\r")
        if line == "":
            if not self.data:
                self.name = ""
                return None
            event = (self.name or "message", "\n".join(self.data), self.t)
            self.name, self.data, self.t = "", [], None
            return event
        field, _, value = line.partition(":")       # a comment (`: keepalive`) has the empty field name: ignored
        if value.startswith(" "):
            value = value[1:]
        if field == "event":
            self.name = value
        elif field == "data":
            if self.t is None:
                self.t = t
            self.data.append(value)
        return None


def openai_event(obj: dict, out: dict) -> tuple[str, str] | None:
    """An OpenAI chat chunk: its first token (kind, text) if it carries one; stats, usage and errors into out."""
    if "error" in obj:
        out["error"] = f"error event: {json.dumps(obj['error'])[:200]}"
        return None
    if obj.get("tensorfold") is not None:
        out["stats"] = obj["tensorfold"]
    if obj.get("usage"):
        u = obj["usage"]
        out["prompt"] = int(u.get("prompt_tokens") or 0)
        out["cached"] = int((u.get("prompt_tokens_details") or {}).get("cached_tokens") or 0)
    token = None
    for choice in obj.get("choices") or ():
        delta = choice.get("delta") or {}
        if delta.get("reasoning_content"):
            token = token or ("reasoning", "")
        if delta.get("content"):
            out["text"].append(delta["content"])
            token = token or ("content", delta["content"])
        if delta.get("tool_calls"):
            token = token or ("tool", "")
    return token


def anthropic_event(name: str, obj: dict, out: dict) -> tuple[str, str] | None:
    """A Messages event: its first token (kind, text) if it carries one; usage, errors and the end into out."""
    kind = obj.get("type") or name
    if kind == "error":
        out["error"] = f"error event: {json.dumps(obj.get('error'))[:200]}"
    elif kind == "message_stop":
        out["done"] = True
    elif kind in ("message_start", "message_delta"):
        u = obj.get("usage") or (obj.get("message") or {}).get("usage") or {}
        if u:
            cached = int(u.get("cache_read_input_tokens") or 0)
            out["cached"] = cached
            out["prompt"] = int(u.get("input_tokens") or 0) + cached + int(u.get("cache_creation_input_tokens") or 0)
    elif kind == "content_block_start":                 # a tool call's block opens with its name: its first token
        if (obj.get("content_block") or {}).get("type") == "tool_use":
            return ("tool", "")
    elif kind == "content_block_delta":
        d = obj.get("delta") or {}
        if d.get("type") == "text_delta" and d.get("text"):
            out["text"].append(d["text"])
            return ("content", d["text"])
        if d.get("type") == "thinking_delta" and d.get("thinking"):
            return ("reasoning", "")
    return None                    # ping, content_block_stop, signature_delta, input_json_delta (after its start)


def stream(url: str, api: str, body: dict, timeout: float = 3600, on_first=None, stop=None) -> dict:
    """One streamed request. ttft / admit are seconds from just before the request is sent."""
    out = {"ttft": None, "admit": None, "first": None, "text": [], "stats": {}, "prompt": 0, "cached": 0,
           "done": False, "error": None}
    data = json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if api == "anthropic":
        headers["anthropic-version"] = "2023-06-01"
    t0 = time.perf_counter()
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, data, headers), timeout=timeout)
    except urllib.error.HTTPError as exc:
        out["error"] = f"HTTP {exc.code}: {exc.read()[:200]!r}"
        return out
    except OSError as exc:
        out["error"] = f"{type(exc).__name__}: {exc}"
        return out
    sse = Sse()
    try:
        with r:
            out["admit"] = time.perf_counter() - t0
            for raw in r:
                event = sse.feed(raw, time.perf_counter())
                if event is not None:
                    name, payload, te = event
                    token = None
                    if api == "openai" and payload == "[DONE]":
                        out["done"] = True
                    else:
                        try:
                            obj = json.loads(payload)
                        except ValueError:
                            out["error"] = f"not JSON: {payload[:120]!r}"
                            break
                        token = (anthropic_event(name, obj, out) if api == "anthropic" else openai_event(obj, out))
                    if token is not None and out["ttft"] is None:
                        out["ttft"], out["first"] = te - t0, token[0]
                        if on_first is not None:
                            on_first()
                    if out["done"] or out["error"]:
                        break
                if stop is not None and stop.is_set():
                    break
    except OSError as exc:
        out["error"] = out["error"] or f"{type(exc).__name__}: {exc}"
    if out["error"] is None and not (stop is not None and stop.is_set()):
        if not out["done"]:
            out["error"] = "the stream ended without its end event"
        elif out["ttft"] is None:
            out["error"] = "the stream ended without a content, reasoning or tool token"
    return out


class Load:
    """N background streams decoding: each its own ~<tokens> prompt (fixed, so cached after its first fill), long
    replies, restarted when one ends, until close()."""

    def __init__(self, url: str, api: str, n: int, tokens: int, max_tokens: int, model: str) -> None:
        self.url, self.api, self.n = url, api, n
        self.stop = threading.Event()
        self.decoding = [False] * n
        self.errors: list[str] = []
        self.bodies = [request_body(api, [{"role": "user", "content": f"[ttft-load {i}]\n" +
                                           filler(tokens, random.Random(4100 + i)) + ASK}], max_tokens, False, model)
                       for i in range(n)]
        self.threads = [threading.Thread(target=self._run, args=(i,), daemon=True) for i in range(n)]

    def _run(self, i: int) -> None:
        while not self.stop.is_set():
            def first() -> None:
                self.decoding[i] = True
            res = stream(self.url, self.api, self.bodies[i], on_first=first, stop=self.stop)
            self.decoding[i] = False
            if res["error"] and not self.stop.is_set():
                self.errors.append(f"stream {i}: {res['error']}")
                self.stop.wait(2)

    def start(self) -> None:
        for t in self.threads:
            t.start()

    def active(self) -> int:
        return sum(self.decoding)

    def ready(self, timeout: float) -> bool:
        end = time.monotonic() + timeout
        while time.monotonic() < end and not self.stop.is_set():
            if self.active() == self.n:
                return True
            time.sleep(0.05)
        return self.active() == self.n

    def close(self) -> None:
        self.stop.set()
        for t in self.threads:
            t.join(30)


# ---- the sample line: written by run(), read back by collect() (one format, one owner) -------------------------
def fmt(v) -> str:
    return "-" if v is None else f"{v:.3f}"


def stat(stats: dict, key: str) -> float | None:
    return float(stats[key]) if stats.get(key) is not None else None


def sample_line(case: str, load: str, res: dict, others: int, flags: list[str]) -> str:
    stats = res["stats"] or {}
    prefill = stat(stats, PREFILL_KEY)
    queue = next((float(stats[k]) for k in QUEUE_KEYS if stats.get(k) is not None), None)
    other = res["ttft"] - res["admit"] - (queue or 0.0) - prefill if prefill is not None else None
    return (f"sample {case} {load} ttft {res['ttft']:.3f} admit {res['admit']:.3f} queue {fmt(queue)} "
            f"prefill {fmt(prefill)} other {fmt(other)} server {fmt(stat(stats, SERVER_TTFT_KEY))} "
            f"prompt {res['prompt']} cached {res['cached']} first {res['first']} others {others}" +
            "".join(f" {f}" for f in flags))


SAMPLE = re.compile(r"sample (?P<case>\S+) (?P<load>\S+) ttft (?P<ttft>[\d.]+) admit (?P<admit>[\d.]+) "
                    r"queue (?P<queue>\S+) prefill (?P<prefill>\S+) other (?P<other>\S+) server (?P<server>\S+) "
                    r"prompt (?P<prompt>\d+) cached (?P<cached>\d+) first (?P<first>\S+) others (?P<others>\d+)"
                    r"(?P<flags>.*)$")
SPLIT = ("admit", "queue", "prefill", "other")


def parse_sample(text: str) -> dict | None:
    m = SAMPLE.match(text)
    if not m:
        return None
    s = {k: (None if m[k] == "-" else float(m[k])) for k in ("ttft", *SPLIT, "server")}
    s.update(case=m["case"], load=m["load"], first=m["first"], flags=m["flags"].split(),
             prompt=int(m["prompt"]), cached=int(m["cached"]), others=int(m["others"]))
    return s


def p90(values: list[float]) -> float:
    s = sorted(values)
    return s[max(0, math.ceil(0.9 * len(s)) - 1)]


def med(values) -> float | None:
    v = [x for x in values if x is not None]
    return statistics.median(v) if v else None


def case_key(case: str):
    m = re.match(r"(cold|warm)([\d.]+k?)(?:-(off|on))?$", case)
    if not m:
        return (2, 0, case)
    return (m[1] == "warm", tokens_of(m[2]), m[3] or "")


def load_key(load: str):
    return (load != "idle", load)


def split_text(ss: list[dict]) -> str:
    return " ".join(f"{k} {fmt(med(s[k] for s in ss))}" for k in (*SPLIT, "server"))


# ---- the harness side: TTFT lines out of a log, grouped by arm ---------------------------------------------------
TAGGED = re.compile(r"^TTFT (?P<arm>\S+) (?P<rest>.*)$")


def collect(lines, group=lambda arm: arm):
    """(samples {(case, load): {group: [sample]}}, errors [line], excluded Counter{group}, groups in order) from log
    lines `TTFT <arm> sample ...` / `TTFT <arm> error ...` / `TTFT <arm> exit <rc>` (the harness's record of the
    probe's exit code: non-zero is an error too, a crash included); other lines are ignored."""
    samples: dict = defaultdict(lambda: defaultdict(list))
    errors: list[str] = []
    excluded: Counter = Counter()
    order: list[str] = []
    for line in lines:
        m = TAGGED.match(line.rstrip("\n"))
        if not m:
            continue
        g = group(m["arm"])
        rest = m["rest"].strip()
        if rest.startswith("error "):
            errors.append(f"{m['arm']} {rest}")
            continue
        rc = re.fullmatch(r"exit (\d+)", rest)
        if rc:
            if rc[1] != "0":
                errors.append(f"{m['arm']} the probe exited {rc[1]}")
            continue
        s = parse_sample(rest)
        if s is None:
            continue
        if g not in order:
            order.append(g)
        if s["flags"]:
            excluded[g] += 1
            continue
        samples[s["case"], s["load"]][g].append(s)
    return samples, errors, excluded, order


def section(samples, errors, excluded, groups, ref=None) -> list[str]:
    """The TTFT section of a summary: per case and load, each group's median / p90 (n) and the change of its median
    against ref (the first group by default); then the split medians; then errors and exclusions."""
    out = []
    if not samples and not errors:
        return ["TTFT: no samples"]
    ref = ref if ref is not None else (groups[0] if groups else None)
    keys = sorted(samples, key=lambda k: (load_key(k[1]), case_key(k[0])))
    out.append(f"TTFT, client-measured to the first streamed token: median / p90 s (n), change of the median vs {ref}")
    out.append("case".ljust(14) + "load".ljust(8) + "".join(g.rjust(26) for g in groups))
    for case, load in keys:
        row = case.ljust(14) + load.ljust(8)
        base = med(s["ttft"] for s in samples[case, load].get(ref, []))
        for g in groups:
            v = [s["ttft"] for s in samples[case, load].get(g, [])]
            if not v:
                row += "-".rjust(26)
                continue
            m = statistics.median(v)
            ch = f" {(m / base - 1) * 100:+.1f}%" if base and g != ref else ""
            row += f"{m:.3f}/{p90(v):.3f} n{len(v)}{ch}".rjust(26)
        out.append(row)
    out.append("TTFT split, medians s: admit (headers) + queue + prefill (server) + other (first decode, gaps) = ttft;"
               " server = the server's own time_to_first_token")
    for case, load in keys:
        for g in groups:
            ss = samples[case, load].get(g, [])
            if ss:
                out.append(f"  {case:13s} {load:7s} {g:14s} {split_text(ss)}  ttft {fmt(med(s['ttft'] for s in ss))}")
    for g in groups:
        if excluded[g]:
            out.append(f"TTFT {g}: {excluded[g]} flagged sample(s) left out (NOTCOLD / NOTWARM / NOLOAD)")
    for e in errors:
        out.append(f"TTFT ERROR {e}")
    return out


def report(paths: list[str]) -> int:
    lines = []
    for p in paths:
        with open(p, errors="replace") as f:
            lines.extend(f)
    samples, errors, excluded, order = collect(lines)
    print("\n".join(section(samples, errors, excluded, order)))
    return 1 if errors else 0


# ---- the probe ---------------------------------------------------------------------------------------------------
def run(args) -> int:
    path = "/v1/messages" if args.api == "anthropic" else "/v1/chat/completions"
    url = f"http://{args.host}:{args.port}{path}"
    cases = [(f"cold{lab}-{th}", tokens_of(lab), th == "on") for lab in args.sizes.split(",") if lab
             for th in args.thinking.split(",") if th]
    warm = args.warm_add != "0"
    if warm:
        cases.append((f"warm{args.warm_add}", tokens_of(args.warm_add), False))
    errors = 0
    done: dict = defaultdict(list)
    flagged: Counter = Counter()
    run_salt = uuid.uuid4().hex[:12]
    base_msgs = [{"role": "user", "content": f"[ttft-warm {run_salt}]\n" +
                  filler(tokens_of(args.warm_base), random.Random(run_salt)) +
                  "\n\nRead the list above. I will ask about it next; reply OK."}]
    prime_body = request_body(args.api, base_msgs, 32, False, args.model)
    conversation = None

    def say(text: str) -> None:
        print(text, flush=True)

    for load in args.loads.split(","):
        n_others = int(load[4:]) if load.startswith("load") else 0
        bg = None
        if n_others:
            bg = Load(url, args.api, n_others, args.load_tokens, args.load_max_tokens, args.model)
            bg.start()
            if not bg.ready(args.load_wait):
                say(f"error load {load} rep 0: only {bg.active()} of {n_others} background streams decoding "
                    f"after {args.load_wait:.0f} s {bg.errors[-1:]}")
                errors += 1
        if warm and conversation is None:            # the kept conversation: its first turn and the reply
            res = stream(url, args.api, prime_body, args.timeout)
            if res["error"]:
                say(f"error warm{args.warm_add} {load} rep 0: priming the kept conversation: {res['error']}")
                errors += 1
            else:
                conversation = base_msgs + [{"role": "assistant", "content": "".join(res["text"])}]
        for rep in range(1, args.reps + 1):
            for case, tokens, thinking in cases:
                salt = uuid.uuid4()
                if case.startswith("warm"):
                    if conversation is None:
                        continue
                    res = stream(url, args.api, prime_body, args.timeout)     # the previous turn, unmeasured
                    if res["error"]:
                        say(f"error {case} {load} rep {rep}: the previous turn: {res['error']}")
                        errors += 1
                        continue
                    msgs = conversation + [{"role": "user", "content": f"[ttft turn {salt}]\n" +
                                            filler(tokens, random.Random(salt.int)) + ASK}]
                else:
                    msgs = [{"role": "user", "content": f"[ttft {salt}]\n" + filler(tokens, random.Random(salt.int)) +
                             ASK}]
                if bg is not None:
                    bg.ready(args.load_wait)
                others = bg.active() if bg is not None else 0
                res = stream(url, args.api, request_body(args.api, msgs, args.max_tokens, thinking, args.model),
                             args.timeout)
                if res["error"]:
                    say(f"error {case} {load} rep {rep}: {res['error']}")
                    errors += 1
                    continue
                flags = []
                if case.startswith("cold") and res["cached"] > 0.05 * max(res["prompt"], 1):
                    flags.append("NOTCOLD")
                if case.startswith("warm") and res["cached"] < 0.5 * max(res["prompt"], 1):
                    flags.append("NOTWARM")
                if others < n_others:
                    flags.append("NOLOAD")
                line = sample_line(case, load, res, others, flags)
                say(line)
                s = parse_sample(line)
                if flags:
                    flagged[case, load] += 1
                else:
                    done[case, load].append(s)
        if bg is not None:
            bg.close()
            for e in bg.errors:
                say(f"error load {load} rep 0: {e}")
                errors += 1
    for case, load in sorted({*done, *flagged}, key=lambda k: (load_key(k[1]), case_key(k[0]))):
        ss = done.get((case, load), [])
        if ss:
            v = [s["ttft"] for s in ss]
            say(f"summary {case} {load} n {len(ss)} ttft med {statistics.median(v):.3f} p90 {p90(v):.3f} " +
                split_text(ss) + f" excluded {flagged[case, load]}")
        else:
            say(f"summary {case} {load} n 0 excluded {flagged[case, load]}")
    return 1 if errors else 0


def main(argv: list[str]) -> int:
    if argv and argv[0] == "report":
        return report(argv[1:])
    ap = argparse.ArgumentParser(description="client-measured time to first token")
    ap.add_argument("port")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--api", choices=("openai", "anthropic"), default="openai")
    ap.add_argument("--model", default="Qwen3.8-Flash-Next")
    ap.add_argument("--sizes", default="1k,8k,32k,120k", help="cold prompt sizes (tokens; k = 1000)")
    ap.add_argument("--thinking", default="off,on")
    ap.add_argument("--warm-base", default="100k", help="the kept conversation's size")
    ap.add_argument("--warm-add", default="2k", help="the warm turn's new tokens (0: no warm case)")
    ap.add_argument("--loads", default="idle,load3", help="idle and/or load<N> (N other streams decoding)")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--max-tokens", type=int, default=16)
    ap.add_argument("--load-tokens", type=int, default=3000)
    ap.add_argument("--load-max-tokens", type=int, default=8192)
    ap.add_argument("--load-wait", type=float, default=600.0, help="seconds to wait for the background streams")
    ap.add_argument("--timeout", type=float, default=3600.0)
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
