#!/usr/bin/env python3
"""rigmark_fake_serve.py <port> <zig|keepall|honour>   a stand-in for the recipe's Zig server's HTTP surface
(tensorfold-native serve), for the offline dry run (test_rigmark_dryrun.sh), stdlib only. Never computes anything.

Routes, shaped as src/server/{status_routes,tokens,openai,sse}.zig answer them:
- GET /health: {"status": "ok", ..., "live": {"connections": N, "waiting": 0, ...}} (N = requests in flight);
- GET /v1/models: one model, "Qwen3.8-Flash-Next";
- POST /tokenize: {"prompt": text} -> one id per character; {"messages": [...], reasoning_effort /
  chat_template_kwargs} -> a rendered prompt whose token_strs carry the template's effort instruction ("Reasoning
  effort is set to low" for low, xhigh by default, none when thinking is off); {"count", "max_model_len", "tokens"};
- POST /v1/chat/completions, /v1/completions: streamed as the Zig server streams: 200 + headers, a role chunk (chat
  only), one chunk a piece (`delta.content` / completion `text`), then a last chunk with `delta: {}` (chat)
  or `text: ""`, the finish reason, `exact_mode`, `tensorfold` (enable_thinking, reasoning_effort, prefill_seconds,
  time_to_first_token) and `usage` - or, when `stream_options.include_usage` is set, `usage` in a chunk of its own
  with `choices: []` - then `data: [DONE]`. Not streamed (chat): one JSON reply with the same blocks.
Reasoning effort is read as fields.zig thinkingFields reads it: a top-level reasoning_effort, else
chat_template_kwargs.reasoning_effort; chat_template_kwargs.enable_thinking wins for the switch.

Its prompt cache (cached_tokens: the longest prefix a request shares with a kept state, floored to a 64-token chunk)
keeps states by one of three rules:
- "zig", the Zig server's (src/core/prompt_cache.zig marks + src/server/prompt.zig history_len): a chat prompt of at
  least MIN_PROMPT tokens keeps its state at its history (the prompt less the generation prompt); a /v1/completions
  token-id prompt has no history and keeps nothing, and cache_salt is not read. So RigMark's prefill pairs are never
  cached (its immediate replay too: spark6's receipts show replay cached 0, replay TTFT = cold TTFT);
- "keepall": every prompt is kept by its token ids, cache_salt ignored: a server RigMark's cold check refuses on a
  second run of one comparison ID;
- "honour": every prompt kept, keyed by its token ids AND the request's cache_salt (what honouring it gives).
The cache lives in the process: a restart empties it, as the Zig server's GPU-memory cache. Replies are canned (the
structured workload's exact answer, short prose / code)."""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, MODE = int(sys.argv[1]), sys.argv[2]
if MODE not in ("zig", "keepall", "honour"):
    raise SystemExit(f"rigmark_fake_serve: mode zig, keepall or honour, not {MODE!r}")
CHUNK = 64
MIN_PROMPT = 4096                   # prompt_cache.zig Rules.min_prompt
KEPT: list = []                     # (salt key, the kept state's tokens)
LOCK = threading.Lock()
LIVE = [0]
STRUCTURED = json.dumps([{"index": i, "square": i * i} for i in range(1, 51)])
EFFORT_TEXT = {"low": "Reasoning effort is set to low. Keep your thinking brief.",
               "xhigh": "Reasoning effort is set to xhigh. Please think carefully."}


def thinking_of(body: dict) -> tuple[bool, str | None]:
    """(thinking, the effort the runtime block reports: None = the template's default, xhigh)."""
    kw = body.get("chat_template_kwargs") or {}
    effort = body.get("reasoning_effort") or kw.get("reasoning_effort")
    on = kw.get("enable_thinking", True if effort is None else effort != "none")
    return bool(on), (effort if on else "none")


def render(messages: list, body: dict) -> tuple[str, int]:
    """(the rendered prompt, its history length: the prompt less the generation prompt)."""
    on, effort = thinking_of(body)
    history = (EFFORT_TEXT.get(effort or "xhigh", "") + "\n" if on else "") + json.dumps(messages)
    return history + ("<think>\n" if on else "<think>\n\n</think>\n\n"), len(history)


def cached_for(salt, prompt: list, history_len: int) -> int:
    key = salt if MODE == "honour" else None
    best = 0
    with LOCK:
        for k, kept in KEPT:
            if k != key:
                continue
            n = 0
            for a, b in zip(kept, prompt):
                if a != b:
                    break
                n += 1
            best = max(best, n)
        if MODE != "zig":
            KEPT.append((key, list(prompt)))
        elif history_len > 0 and len(prompt) >= MIN_PROMPT:
            KEPT.append((key, list(prompt[:history_len])))
    return min(best, len(prompt) - 1) // CHUNK * CHUNK if best else 0


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            return self._json(200, {"object": "list", "data": [{"id": "Qwen3.8-Flash-Next", "object": "model",
                                                                 "owned_by": "tensorfold"}]})
        if self.path.rstrip("/") == "/health":
            return self._json(200, {"status": "ok", "model": "Qwen3.8-Flash-Next", "max_batch_size": 8,
                                    "warming": False, "memory": {},
                                    "live": {"connections": LIVE[0], "waiting": 0, "decode_tokens_per_second": 0.0,
                                             "prefill_tokens_per_second": 0.0}})
        return self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        path = self.path.rstrip("/")
        if path == "/tokenize":
            text = render(body["messages"], body)[0] if "messages" in body else body.get("prompt", "")
            out = {"count": len(text), "max_model_len": 262144, "tokens": [ord(c) % 50000 for c in text]}
            if body.get("return_token_strs"):
                out["token_strs"] = [c.replace(" ", "\u0120").replace("\n", "\u010a") for c in text]
            return self._json(200, out)
        if path not in ("/v1/chat/completions", "/v1/completions"):
            return self._json(404, {"error": {"message": "not found"}})
        chat = path.endswith("chat/completions")
        on, effort = thinking_of(body)
        if chat:
            text, history_len = render(body["messages"], body)
            prompt = [ord(c) % 50000 for c in text]
            user = body["messages"][-1]["content"]
            reply = STRUCTURED if "square" in user else ("def answer():\n    return 42\n" if "code" in user.lower()
                                                         else "A short paragraph of prose. " * 4)
            pieces = [reply[i:i + 8] for i in range(0, len(reply), 8)]
            finish = "stop"
        else:
            on, effort = False, "none"
            prompt, history_len = list(body["prompt"]), 0     # token ids: no history (prompt.zig)
            pieces = ["x"] * int(body.get("max_tokens", 8))
            finish = "length"
        cached = cached_for(body.get("cache_salt"), prompt, history_len)
        runtime = {"enable_thinking": on, "reasoning_effort": effort, "engine": "fake", "prefill_seconds": 0.001,
                   "time_to_first_token": 0.002, "sampling": "exact", "drafts": True}
        usage = {"prompt_tokens": len(prompt), "completion_tokens": len(pieces),
                 "total_tokens": len(prompt) + len(pieces), "prompt_tokens_details": {"cached_tokens": cached},
                 "completion_tokens_details": {"reasoning_tokens": 0}}
        if not body.get("stream"):
            text = "".join(pieces)
            choice = ({"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": finish}
                      if chat else {"index": 0, "text": text, "finish_reason": finish, "logprobs": None})
            return self._json(200, {"id": "chatcmpl-fake", "object": "chat.completion" if chat else "text_completion",
                                    "choices": [choice], "usage": usage, "exact_mode": "exact",
                                    "tensorfold": runtime, "speculative": {"rounds": 1}})
        LIVE[0] += 1
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()

            def emit(obj):
                self.wfile.write(f"data: {json.dumps(obj)}\n\n".encode())
                self.wfile.flush()

            def chunk(piece, fin=None):
                c = {"index": 0, "finish_reason": fin}
                if chat:
                    c["delta"] = piece if isinstance(piece, dict) else ({"content": piece} if piece else {})
                else:
                    c.update(text=piece, logprobs=None)
                return {"id": "chatcmpl-fake", "object": "chat.completion.chunk" if chat else "text_completion",
                        "created": 1, "model": "Qwen3.8-Flash-Next", "choices": [c]}

            if chat:
                emit(chunk({"role": "assistant"}))
            for piece in pieces:
                time.sleep(0.002)
                emit(chunk(piece))
            last = chunk("", finish)
            last.update(exact_mode="exact", tensorfold=runtime, speculative={"rounds": len(pieces)})
            separate = bool((body.get("stream_options") or {}).get("include_usage"))
            if not separate:
                last["usage"] = usage
            emit(last)
            if separate:
                u = chunk("")
                u["choices"] = []
                u["usage"] = usage
                emit(u)
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        finally:
            LIVE[0] -= 1
        self.close_connection = True


srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
srv.daemon_threads = True
srv.serve_forever()
