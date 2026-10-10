"""CPU-only, no GPU, no serve: ttft.py against a fake server streaming the recipe's Zig server's shape on a loopback
port, so the probe can FAIL.

  python3 -B test_ttft.py [--probe path/to/ttft.py] [--scripts-dir dir with zab_rm_sum.py]

The fake streams as the Zig server does (src/server/openai.zig, sse.zig): the 200 after the prompt is rendered, then at
once a role chunk, then `data:` chunks of `content` / `reasoning_content` deltas, then a last chunk with `delta: {}`
(as the live server sends it, 2026-10-10), the finish reason, `exact_mode`, the `tensorfold` runtime block
(`prefill_seconds`, `time_to_first_token`) and `usage` (or `usage` in a chunk of its own with `choices: []` when the
request sets `stream_options.include_usage`), then `data: [DONE]`; a failure mid-stream is a `data: {"error": ...}`
chunk and `[DONE]`. Its Messages route streams `message_start`, an empty `content_block_start`, deltas,
`message_delta`, `message_stop`. Variants stress the parser beyond what the Zig server sends: `: keepalive` comments,
an empty delta and an Anthropic `ping` while the reply is silent (mode keepalive), CRLF line ends, a JSON chunk split
over two `data:` lines. It holds the response headers back ADMIT s and the first token SILENT s more, so a probe that
times from the headers, counts the role chunk, a comment, a ping, an empty delta or a later token reports the wrong
number.
Checks:
- stream(): TTFT in [ADMIT + SILENT, + 0.12 s), admit ~ADMIT, the first token's kind (content / reasoning), the
  server's prefill_seconds, time_to_first_token and (in a variant) queue_s, prompt / cached tokens (in the last chunk
  and in a separate usage chunk), on both routes; errors (an error event on both routes, a stream with no end, one
  with no token, HTTP 429) reported as errors with no TTFT;
- the whole CLI (cold sizes x thinking off / on, the warm turn, idle and load3): the right sample count, every load3
  sample sent while the fake had exactly 3 background streams decoding (and idle ones while it had 0), the kept
  conversation re-sent before every warm turn, warm turns cached and cold ones not, the background streams gone at
  the end, exit 0; and on the Anthropic route; NOTCOLD / NOTWARM / NOLOAD flags on a cold prompt that hit, a warm turn
  that missed, a load the fake refused;
- collect() / section() / p90 on known numbers (flagged samples left out, error and non-zero exit lines kept), the
  report subcommand, and zab_rm_sum.py on synthetic logs (TTFT ours vs base, golden MATCH / DIFF, exit codes).
Prints PASS/FAIL per check and FAILED at the end (exit 1) on any failure. Mutants: mutants_ttft.py.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ADMIT = 0.2                 # headers held back (render + tokenize)
SILENT = 0.35               # then silence before the first token
PREFILL = 0.42              # the runtime block's prefill_seconds
SERVER_TTFT = 0.51          # the runtime block's time_to_first_token
HERE = Path(__file__).resolve().parent

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"{'PASS' if ok else 'FAIL'} {name}{': ' + detail if detail and not ok else ''}", flush=True)
    if not ok:
        failures.append(f"  {name}: {detail}")


class Fake:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.active = 0             # background streams that have sent a token and not ended
        self.arrivals: list[tuple[str, int]] = []   # measured / prime requests: (tag, active at arrival)
        self.assistant: list[str] = []          # the assistant turn every conversation request carried
        self.mode: dict = {}


FAKE = Fake()


def expected_usage(msgs: list[dict]) -> tuple[int, int]:
    """The fake's (prompt, cached) for a request's messages: a conversation (2+ messages) is 95% cached, a single
    prompt not at all; FAKE.mode["cache"] = "all" / "none" overrides (a cold prompt that hit, a warm turn that missed)."""
    prompt = len(json.dumps(msgs)) // 4
    hit = {"all": True, "none": False}.get(FAKE.mode.get("cache"), len(msgs) > 1)
    return prompt, int(prompt * 0.95) if hit else 0


def chunk(delta: dict | None, finish: str | None = None) -> dict:
    """A Zig chat.completion.chunk (openai.zig Run.chunk)."""
    return {"id": "chatcmpl-x", "object": "chat.completion.chunk", "created": 1, "model": "Qwen3.8-Flash-Next",
            "choices": [{"index": 0, "delta": delta if delta is not None else {}, "finish_reason": finish}]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def w(self, text: str) -> None:
        if FAKE.mode.get("crlf"):
            text = text.replace("\n", "\r\n")
        self.wfile.write(text.encode())

    def ev(self, api: str, obj: dict) -> None:
        if api == "anthropic":
            self.w(f"event: {obj['type']}\ndata: {json.dumps(obj)}\n\n")
            return
        s = json.dumps(obj)
        if FAKE.mode.get("multiline") and ", " in s:
            i = s.index(", ")
            self.w(f"data: {s[:i + 1]}\ndata: {s[i + 2:]}\n\n")
        else:
            self.w(f"data: {s}\n\n")

    def delta(self, api: str, kind: str, text: str, index: int = 0) -> None:
        if api == "anthropic":
            key = "thinking" if kind == "reasoning" else "text"
            self.ev(api, {"type": "content_block_delta", "index": index, "delta": {"type": key + "_delta", key: text}})
        else:
            self.ev(api, chunk({"reasoning_content" if kind == "reasoning" else "content": text}))

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        api = "anthropic" if self.path.endswith("/messages") else "openai"
        msgs = body["messages"]
        last = msgs[-1]["content"]
        thinking = ((body.get("thinking") or {}).get("type", "disabled") != "disabled" if api == "anthropic"
                    else bool((body.get("chat_template_kwargs") or {}).get("enable_thinking")))
        prompt, cached = expected_usage(msgs)
        if "[ttft-load" in last:
            return self.background(api, body["max_tokens"])
        mode = FAKE.mode
        time.sleep(mode.get("admit", ADMIT))
        with FAKE.lock:         # recorded after the admission delay: a stream the client closed has noticed by then
            FAKE.arrivals.append((last.split("]")[0].split()[0].lstrip("[") if last.startswith("[") else "?",
                                  FAKE.active))
            if len(msgs) > 1:
                FAKE.assistant.append(msgs[1]["content"])
        if mode.get("status"):
            data = json.dumps({"error": {"message": "the engine is busy; retry shortly"}}).encode()
            self.send_response(mode["status"])
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        if api == "anthropic":
            self.ev(api, {"type": "message_start", "message": {"role": "assistant", "content": [], "usage": {
                "input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0}}})
            self.ev(api, {"type": "content_block_start", "index": 0, "content_block":
                          {"type": "thinking", "thinking": ""} if thinking else {"type": "text", "text": ""}})
        else:
            self.ev(api, chunk({"role": "assistant"}))
        silent = mode.get("silent", SILENT)
        t_end = time.monotonic() + silent
        sent_empty = False
        while time.monotonic() < t_end:
            if mode.get("keepalive"):
                self.w(": keepalive\n\n")
                if not sent_empty and time.monotonic() > t_end - silent / 2:
                    if api == "openai":
                        self.ev(api, chunk({"content": ""}))
                    else:
                        self.ev(api, {"type": "ping"})
                    sent_empty = True
            time.sleep(min(0.05, max(0.0, t_end - time.monotonic())))
        if mode.get("error"):
            if api == "anthropic":
                self.ev(api, {"type": "error", "error": {"type": "api_error", "message": "boom"}})
            else:
                self.w('data: {"error": {"message": "boom", "type": "server_error"}}\n\ndata: [DONE]\n\n')
            return
        if mode.get("tool"):                     # a reply that starts with a tool call
            if api == "anthropic":
                self.ev(api, {"type": "content_block_stop", "index": 0})
                self.ev(api, {"type": "content_block_start", "index": 1, "content_block":
                              {"type": "tool_use", "id": "c1", "name": "read", "input": {}}})
                time.sleep(0.15)
                self.ev(api, {"type": "content_block_delta", "index": 1,
                              "delta": {"type": "input_json_delta", "partial_json": "{}"}})
            else:
                self.ev(api, chunk({"tool_calls": [{"index": 0, "id": "c1", "type": "function",
                                                    "function": {"name": "read", "arguments": "{}"}}]}))
        elif not mode.get("no_token"):
            self.delta(api, "reasoning" if thinking else "content", "Hi")
            for _ in range(2):
                time.sleep(0.15)
                self.delta(api, "content" if not thinking else "reasoning", " more")
        if mode.get("no_done"):
            return
        stats = {"enable_thinking": thinking, "reasoning_effort": None if thinking else "none",
                 "engine": "lanes", "tokens_per_second": 50.0, "seconds": 1.0, "prefill_seconds": PREFILL,
                 "prefill_widths": [], "prefill_raised": [], "time_to_first_token": SERVER_TTFT,
                 "sampling": "greedy", "drafts": True, "token_sha": "7854e4db3a72", "min_rows": 5}
        if mode.get("python"):                   # TensorFold v0.6.1's Python server: cuda/streams.py Stream.stats
            stats = {"prefill_s": PREFILL, "decode_s": 0.3, "rounds": 2, "drafts": True, "cached": cached,
                     "min_rows": 2, "drafted": 3, "accepted": 1, "token_sha": "7854e4db3a72"}
        if "queue_s" in mode:
            stats["queue_s"] = mode["queue_s"]
        usage = {"prompt_tokens": prompt, "completion_tokens": 3, "total_tokens": prompt + 3,
                 "prompt_tokens_details": {"cached_tokens": cached},
                 "completion_tokens_details": {"reasoning_tokens": 3 if thinking else 0}}
        if api == "anthropic":
            self.ev(api, {"type": "content_block_stop", "index": 0})
            self.ev(api, {"type": "message_delta", "delta": {"stop_reason": "max_tokens"}, "usage": {
                "input_tokens": prompt - cached, "output_tokens": 3, "cache_read_input_tokens": cached,
                "cache_creation_input_tokens": 0}})
            self.ev(api, {"type": "message_stop"})
            return
        last_chunk = chunk({}, "length")
        last_chunk.update(exact_mode="exact", tensorfold=stats, speculative={"rounds": 3, "drafted": 4,
                                                                             "accepted": 2})
        separate = bool((body.get("stream_options") or {}).get("include_usage"))
        if not separate:
            last_chunk["usage"] = usage
        self.ev(api, last_chunk)
        if separate:
            u = chunk(None)
            u["choices"] = []
            u["usage"] = usage
            self.ev(api, u)
        self.w("data: [DONE]\n\n")

    def background(self, api: str, max_tokens: int) -> None:
        if FAKE.mode.get("bg_status"):
            data = b'{"error": {"message": "full"}}'
            self.send_response(FAKE.mode["bg_status"])
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        counted = False
        try:
            if api == "anthropic":
                self.ev(api, {"type": "message_start", "message": {"role": "assistant", "usage": {}}})
            else:
                self.ev(api, chunk({"role": "assistant"}))
            time.sleep(FAKE.mode.get("bg_delay", 0.05))     # the restart's fill, before its first token
            for i in range(max_tokens):
                self.delta(api, "content", f" t{i}")
                if not counted:
                    with FAKE.lock:
                        FAKE.active += 1
                    counted = True
                time.sleep(0.02)
            self.w("data: [DONE]\n\n" if api == "openai" else 'event: message_stop\ndata: {"type": "message_stop"}\n\n')
        except OSError:
            pass
        finally:
            if counted:
                with FAKE.lock:
                    FAKE.active -= 1


def load_probe(path: Path):
    spec = importlib.util.spec_from_file_location("ttft", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def body(tt, api: str, thinking: bool, content: str = "[ttft x]\nhello"):
    return tt.request_body(api, [{"role": "user", "content": content}], 16, thinking, "Qwen3.8-Flash-Next")


def in_window(res) -> bool:
    return res["ttft"] is not None and ADMIT + SILENT - 0.01 <= res["ttft"] < ADMIT + SILENT + 0.12


def test_stream(tt, port: int) -> None:
    check("request body: thinking via chat_template_kwargs.enable_thinking",
          body(tt, "openai", True)["chat_template_kwargs"] == {"enable_thinking": True} and
          body(tt, "openai", False)["chat_template_kwargs"] == {"enable_thinking": False},
          json.dumps(body(tt, "openai", True)))
    for api, path in (("openai", "/v1/chat/completions"), ("anthropic", "/v1/messages")):
        url = f"http://127.0.0.1:{port}{path}"
        for thinking in (False, True):
            for extra in ({}, {"keepalive": True}, {"crlf": True}, {"multiline": True}, {"queue_s": 0.11},
                          {"separate_usage": True}, {"python": True}):
                FAKE.mode = dict(extra)
                name = f"{api} thinking {'on' if thinking else 'off'} {','.join(extra) or 'zig'}"
                b = body(tt, api, thinking)
                if extra.get("separate_usage"):
                    b["stream_options"] = {"include_usage": True}
                res = tt.stream(url, api, b)
                check(f"{name}: no error", res["error"] is None, str(res["error"]))
                check(f"{name}: ttft is the first token's", in_window(res),
                      f"ttft {res['ttft']} not in [{ADMIT + SILENT:.2f}, {ADMIT + SILENT + 0.12:.2f})")
                check(f"{name}: admit is the headers'", res["admit"] is not None and
                      ADMIT - 0.01 <= res["admit"] < ADMIT + 0.1, f"admit {res['admit']}")
                want = "reasoning" if thinking else "content"
                check(f"{name}: first is {want}", res["first"] == want, f"first {res['first']}")
                msgs = [{"role": "user", "content": "[ttft x]\nhello"}]
                check(f"{name}: prompt / cached tokens", (res["prompt"], res["cached"]) == expected_usage(msgs),
                      f"{res['prompt']} / {res['cached']}, want {expected_usage(msgs)}")
                if res["ttft"] is None or res["admit"] is None:     # already FAILed above; no sample line to read
                    continue
                line = tt.sample_line("cold1k-off", "idle", res, 0, [])
                s = tt.parse_sample(line)
                check(f"{name}: sample line parses", s is not None and abs(s["ttft"] - res["ttft"]) < 0.002, line)
                if s is None:
                    continue
                if api == "openai":
                    check(f"{name}: prefill_seconds (the Python server's prefill_s)", s["prefill"] == PREFILL, line)
                    want_server = None if extra.get("python") else SERVER_TTFT
                    check(f"{name}: the server's time_to_first_token", s["server"] == want_server, line)
                    q = extra.get("queue_s")
                    check(f"{name}: queue", s["queue"] == q, line)
                    want_other = res["ttft"] - res["admit"] - (q or 0) - PREFILL
                    check(f"{name}: other = ttft - admit - queue - prefill",
                          s["other"] is not None and abs(s["other"] - want_other) < 0.002, line)
                else:
                    check(f"{name}: no prefill or server ttft on the Messages route",
                          s["prefill"] is None and s["other"] is None and s["server"] is None, line)
    for api, path in (("openai", "/v1/chat/completions"), ("anthropic", "/v1/messages")):
        url = f"http://127.0.0.1:{port}{path}"
        for mode, want in (({"error": True, "silent": 0.1}, "error event"),
                           ({"no_done": True, "silent": 0.1}, "without its end event"),
                           ({"no_token": True, "silent": 0.1}, "without a content"),
                           ({"status": 429}, "HTTP 429")):
            FAKE.mode = mode
            res = tt.stream(url, api, body(tt, api, False))
            ok = res["error"] is not None and want in res["error"]
            if "no_done" not in mode:               # the no-end stream did send a token; the others never did
                ok = ok and res["ttft"] is None
            check(f"{api} {next(iter(mode))}: reported as an error", ok, f"error {res['error']!r} ttft {res['ttft']}")
    for api, path in (("openai", "/v1/chat/completions"), ("anthropic", "/v1/messages")):
        FAKE.mode = {"silent": 0.05}             # a conversation: the fake reports it 95% cached
        msgs = [{"role": "user", "content": "[ttft-warm a]\nhello"}, {"role": "assistant", "content": "OK"},
                {"role": "user", "content": "[ttft turn b]\nmore"}]
        res = tt.stream(f"http://127.0.0.1:{port}{path}", api,
                        tt.request_body(api, msgs, 16, False, "Qwen3.8-Flash-Next"))
        check(f"{api} conversation: prompt / cached tokens", (res["prompt"], res["cached"]) == expected_usage(msgs)
              and res["cached"] > 0, f"{res['prompt']} / {res['cached']}, want {expected_usage(msgs)}")
    for api, path in (("openai", "/v1/chat/completions"), ("anthropic", "/v1/messages")):
        FAKE.mode = {"tool": True}
        res = tt.stream(f"http://127.0.0.1:{port}{path}", api, body(tt, api, False))
        check(f"{api} tool call first: a token, at its start", res["error"] is None and res["first"] == "tool" and
              in_window(res), f"{res['error']} first {res['first']} ttft {res['ttft']}")
    FAKE.mode = {}


def run_cli(probe: Path, port: int, *extra: str, timeout: float = 300):
    r = subprocess.run([sys.executable, "-B", str(probe), str(port), "--load-tokens", "100", "--load-wait", "20",
                        "--timeout", "60", *extra], capture_output=True, text=True, timeout=timeout)
    out = r.stdout.splitlines()
    return r, out, [ln for ln in out if ln.startswith("sample ")]


def flags_of(line: str) -> list[str]:
    return line.split(" others ")[1].split()[1:]


def test_cli(probe: Path, port: int) -> None:
    FAKE.mode = {"silent": 0.15, "admit": 0.15}
    FAKE.arrivals.clear()
    FAKE.assistant.clear()
    # load3 FIRST: the idle series after it shows that the background streams were closed
    r, out, samples = run_cli(probe, port, "--sizes", "1k,2k", "--thinking", "off,on", "--reps", "2",
                              "--warm-base", "3k", "--warm-add", "500", "--loads", "load3,idle",
                              "--load-max-tokens", "100000")
    check("cli: exit 0", r.returncode == 0, f"exit {r.returncode}: {r.stdout[-400:]} {r.stderr[-400:]}")
    check("cli: 20 samples (5 cases x 2 reps x 2 loads)", len(samples) == 20, f"{len(samples)}: {out[:3]}")
    check("cli: 10 summary lines, n 2 each", [ln.split()[4] for ln in out if ln.startswith("summary ")] == ["2"] * 10,
          "\n".join(out[-12:]))
    check("cli: no flagged sample", not any(flags_of(ln) for ln in samples),
          "\n".join(ln for ln in samples if flags_of(ln)))
    load_n = [int(ln.split("others ")[1].split()[0]) for ln in samples if " load3 " in ln]
    idle_n = [int(ln.split("others ")[1].split()[0]) for ln in samples if " idle " in ln]
    check("cli: load3 samples sent with 3 others decoding", load_n == [3] * 10, str(load_n))
    check("cli: idle samples with none", idle_n == [0] * 10, str(idle_n))
    measured = [(t, a) for t, a in FAKE.arrivals if t in ("ttft", "ttft-warm")]
    # load3: the prime, then per rep 4 cold, the previous turn again, the warm turn (2 x 6); idle: 2 x 6, no prime
    check("cli: 25 measured / prime requests (1 + 12 at load3, 12 idle)", len(measured) == 25, str(measured))
    check("cli: the fake saw 3 background streams at every load3 request (and the prime)",
          [a for _, a in measured[:13]] == [3] * 13, str(measured))
    check("cli: and none at the idle ones after them (closed)", [a for _, a in measured[13:]] == [0] * 12,
          str(measured))
    primes = [t for t, _ in FAKE.arrivals if t == "ttft-warm"]
    check("cli: the kept conversation's first turn re-sent before every warm turn (1 + 4 x prime)",
          len(primes) == 5, str(primes))
    warm = [ln for ln in samples if ln.startswith("sample warm500 ")]
    check("cli: warm turns cached", len(warm) == 4 and all(int(ln.split(" cached ")[1].split()[0]) > 0 for ln in warm),
          "\n".join(warm))
    check("cli: the warm turns carry the prime's reply verbatim", FAKE.assistant == ["Hi more more"] * 4,
          str(FAKE.assistant))
    cold = [ln for ln in samples if ln.startswith("sample cold")]
    check("cli: cold prompts not cached", len(cold) == 16 and all(" cached 0 " in ln for ln in cold), "\n".join(cold))
    ttfts = [float(ln.split(" ttft ")[1].split()[0]) for ln in samples]
    check("cli: every ttft past admit + silence", all(t >= 0.29 for t in ttfts), str(ttfts))
    think = [ln.split(" first ")[1].split()[0] for ln in samples if "-on " in ln]
    check("cli: thinking on starts with reasoning", think and set(think) == {"reasoning"}, str(think))
    check("cli: the server's ttft and prefill on every sample",
          all(f" prefill {PREFILL:.3f} " in ln and f" server {SERVER_TTFT:.3f} " in ln for ln in samples),
          "\n".join(samples[:2]))
    time.sleep(0.3)
    check("cli: background streams closed", FAKE.active == 0, f"{FAKE.active} still decoding")
    # churn: background replies of 30 tokens, 0.3 s to their first token: a measured request must wait for all 3
    FAKE.mode = {"silent": 0.05, "admit": 0.0, "bg_delay": 0.3}
    r, out, samples = run_cli(probe, port, "--sizes", "1k", "--thinking", "off", "--reps", "8", "--warm-add", "0",
                              "--loads", "load3", "--load-max-tokens", "30")
    check("cli churn: every sample sent while all 3 decoded", r.returncode == 0 and len(samples) == 8 and
          not any(flags_of(ln) for ln in samples), r.stdout[-800:] + r.stderr[-300:])
    time.sleep(0.3)
    FAKE.mode = {"silent": 0.05, "admit": 0.0, "cache": "all"}
    r, out, samples = run_cli(probe, port, "--sizes", "1k", "--thinking", "off", "--reps", "1", "--warm-add", "0",
                              "--loads", "idle")
    check("cli: a cold prompt that hit the cache is flagged NOTCOLD and left out", r.returncode == 0 and
          len(samples) == 1 and flags_of(samples[0]) == ["NOTCOLD"] and
          "summary cold1k-off idle n 0 excluded 1" in out, r.stdout)
    FAKE.mode = {"silent": 0.05, "admit": 0.0, "cache": "none"}
    r, out, samples = run_cli(probe, port, "--sizes", "1k", "--thinking", "off", "--reps", "1", "--warm-base", "1k",
                              "--warm-add", "100", "--loads", "idle")
    warm = [ln for ln in samples if ln.startswith("sample warm100 ")]
    cold = [ln for ln in samples if ln.startswith("sample cold1k-off ")]
    check("cli: a warm turn that missed the cache is flagged NOTWARM (a cold prompt is not)", r.returncode == 0 and
          len(warm) == 1 and flags_of(warm[0]) == ["NOTWARM"] and "summary warm100 idle n 0 excluded 1" in out and
          len(cold) == 1 and flags_of(cold[0]) == [], r.stdout)
    FAKE.mode = {"silent": 0.15, "admit": 0.05}
    r, out, s = run_cli(probe, port, "--api", "anthropic", "--sizes", "1k", "--thinking", "on", "--reps", "1",
                        "--warm-add", "0", "--loads", "load3", "--load-max-tokens", "100000", timeout=120)
    check("cli anthropic: one sample, reasoning first, 3 others, no prefill", r.returncode == 0 and len(s) == 1 and
          " first reasoning others 3" in s[0] and " prefill - " in s[0], r.stdout[-500:] + r.stderr[-300:])
    time.sleep(0.3)
    FAKE.mode = {"status": 429, "admit": 0.0}
    r, out, s = run_cli(probe, port, "--sizes", "1k", "--thinking", "off", "--reps", "1", "--warm-add", "0",
                        "--loads", "idle", timeout=60)
    check("cli: a refused request is an error line and exit 1", r.returncode == 1 and
          any(ln.startswith("error cold1k-off idle rep 1: HTTP 429") for ln in out), r.stdout)
    FAKE.mode = {}
    time.sleep(0.3)
    FAKE.mode = {"silent": 0.05, "admit": 0.0, "bg_status": 429}
    r, out, s = run_cli(probe, port, "--sizes", "1k", "--thinking", "off", "--reps", "1", "--warm-add", "0",
                        "--loads", "load3", "--load-wait", "1", timeout=60)
    check("cli: refused background streams: their errors, the sample flagged NOLOAD, exit 1", r.returncode == 1 and
          any(ln.startswith("error load load3 rep 0: only 0 of 3") for ln in out) and
          any(ln.startswith("error load load3 rep 0: stream ") and "HTTP 429" in ln for ln in out) and
          len(s) == 1 and flags_of(s[0]) == ["NOLOAD"], r.stdout)
    FAKE.mode = {}
    time.sleep(0.3)


def sample(case, load, ttft, prefill=1.0, flags=""):
    return (f"sample {case} {load} ttft {ttft:.3f} admit 0.010 queue - prefill {prefill:.3f} "
            f"other {ttft - 0.01 - prefill:.3f} server {ttft - 0.005:.3f} prompt 1000 cached 0 first content others "
            f"{3 if load == 'load3' else 0}{flags}")


GOLD_OK = "GOLD {a} /home/adam/work/zgold-zrm-x-{a}.json: 6/6 identical to /home/adam/work/zab3/zgold-base-c1.json\n"


def test_report(tt, probe: Path, scripts: Path) -> None:
    check("p90 nearest rank", tt.p90([float(i) for i in range(1, 11)]) == 9.0 and tt.p90([2.0]) == 2.0 and
          tt.p90([1.0, 2.0, 3.0]) == 3.0, f"{tt.p90([float(i) for i in range(1, 11)])}")
    lines = []
    for arm, vals in (("a1", (1.0, 2.0, 3.0)), ("b1", (2.0, 4.0, 6.0)), ("a2", (5.0,))):
        lines += [f"TTFT {arm} {sample('cold8k-off', 'idle', v)}\n" for v in vals]
    lines += [f"TTFT a1 {sample('cold8k-off', 'idle', 99.0, flags=' NOTCOLD')}\n",
              "TTFT b1 error cold1k-on load3 rep 2: HTTP 429\n", "TTFT b1 exit 1\n", "TTFT a1 exit 0\n",
              f"TTFT a1 {sample('cold120k-on', 'load3', 9.0)}\n", f"TTFT a1 {sample('cold32k-off', 'idle', 4.0)}\n",
              f"TTFT a1 {sample('warm2k', 'idle', 0.5)}\n", "noise TTFT a1 sample x\n"]
    samples, errors, excluded, order = tt.collect(lines, group=lambda a: a.rstrip("0123456789"))
    v = sorted(s["ttft"] for s in samples["cold8k-off", "idle"]["a"])
    check("collect: grouped, flagged left out", v == [1.0, 2.0, 3.0, 5.0] and excluded["a"] == 1, f"{v} {excluded}")
    check("collect: error and non-zero exit lines kept, exit 0 not", len(errors) == 2 and
          "HTTP 429" in errors[0] and "exited 1" in errors[1], str(errors))
    sec = tt.section(samples, errors, excluded, order)
    row = next((ln for ln in sec if ln.startswith("cold8k-off")), "")
    check("section: medians / p90 / n / change", "2.500/5.000 n4" in row and "4.000/6.000 n3 +60.0%" in row, row)
    keys = [ln.split()[0] for ln in sec if ln[:4] in ("cold", "warm")]
    check("section: cases in size order, idle before load", keys == ["cold8k-off", "cold32k-off", "warm2k",
                                                                      "cold120k-on"], str(keys))
    check("section: errors and exclusions shown", any("TTFT ERROR" in ln and "HTTP 429" in ln for ln in sec) and
          any("1 flagged" in ln for ln in sec), "\n".join(sec))
    split = next((ln for ln in sec if ln.strip().startswith("cold8k-off") and " a " in ln), "")
    check("section: split medians", "admit 0.010 queue - prefill 1.000 other 1.490 server 2.495" in split, split)
    with tempfile.TemporaryDirectory() as d:
        log = Path(d) / "x.log"
        log.write_text("".join(lines))
        r = subprocess.run([sys.executable, "-B", str(probe), "report", str(log)], capture_output=True,
                           text=True)
        check("report subcommand: section, exit 1 on errors", r.returncode == 1 and "cold8k-off" in r.stdout, r.stdout)
        zsum = scripts / "zab_rm_sum.py"
        ttft_lines = [f"TTFT {arm} {sample('cold1k-off', 'idle', v)}\n" for arm, v in
                      (("ours", 0.8), ("ours", 0.6), ("base", 1.0), ("base", 1.2))]
        good = ("== 01:00:00 ZABRM x START: comparison zrm-x order ours base base=PREPARE=0 ours=PREPARE=0\n" +
                GOLD_OK.format(a="ours") + "GOLD ours exit 0\n" + "".join(ttft_lines[:2]) + "TTFT ours exit 0\n" +
                GOLD_OK.format(a="base") + "GOLD base exit 0\n" + "".join(ttft_lines[2:]) + "TTFT base exit 0\n" +
                "EFFORT ours effort OK\nEFFORT ours exit 0\n")
        log.write_text(good)
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        row = next((ln for ln in r.stdout.splitlines() if ln.startswith("cold1k-off")), "")
        check("zab_rm_sum: golden MATCH, TTFT section base first, ours vs base, exit 0", r.returncode == 0 and
              "golden base: 6/6 MATCH" in r.stdout and "golden ours: 6/6 MATCH" in r.stdout and
              "1.100/1.200 n2" in row and "0.700/0.800 n2 -36.4%" in row and row.index("1.100") < row.index("0.700"),
              r.stdout + r.stderr)
        log.write_text(good.replace("6/6 identical", "5/6 identical", 1).replace("GOLD ours exit 0", "GOLD ours exit 1"))
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        check("zab_rm_sum: a golden DIFF exits 1", r.returncode == 1 and "golden ours: 5/6 DIFF" in r.stdout,
              r.stdout + r.stderr)
        log.write_text(good.replace(GOLD_OK.format(a="base") + "GOLD base exit 0\n", ""))
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        check("zab_rm_sum: an arm that ran without a golden verdict exits 1", r.returncode == 1 and
              "golden base: NO VERDICT" in r.stdout, r.stdout + r.stderr)
        log.write_text(good + "TTFT base error warm2k idle rep 1: boom\n")
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        check("zab_rm_sum: a TTFT probe error exits 1", r.returncode == 1 and "TTFT ERROR base" in r.stdout,
              r.stdout + r.stderr)
        log.write_text(good + "EFFORT base effort FAILED: the reply ran enable_thinking False reasoning_effort none\n")
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        check("zab_rm_sum: an effort failure exits 1", r.returncode == 1 and "ERROR effort base" in r.stdout,
              r.stdout + r.stderr)
        log.write_text(good + "BOOT ours FAILED: /health does not answer\n")
        r = subprocess.run([sys.executable, "-B", str(zsum), str(log)], capture_output=True, text=True)
        check("zab_rm_sum: a boot failure exits 1", r.returncode == 1 and "ERROR boot ours" in r.stdout,
              r.stdout + r.stderr)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", default=str(HERE.parent / "ttft.py"))
    ap.add_argument("--scripts-dir", default=str(HERE.parent))
    a = ap.parse_args()
    probe = Path(a.probe).resolve()
    tt = load_probe(probe)
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    port = srv.server_address[1]
    try:
        for part in (lambda: test_stream(tt, port), lambda: test_cli(probe, port),
                     lambda: test_report(tt, probe, Path(a.scripts_dir).resolve())):
            try:
                part()
            except Exception as exc:     # the probe raised under the test: a failure, with where it came from
                check("a test part ran to its end", False, "".join(traceback.format_exception(exc))[-800:])
    finally:
        srv.shutdown()
    if failures:
        print("FAILED")
        print("\n".join(failures))
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")
    sys.exit(main())
