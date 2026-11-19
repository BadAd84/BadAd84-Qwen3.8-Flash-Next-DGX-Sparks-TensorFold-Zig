"""One OpenAI-compatible client for the A/B quality comparison, identical for both arms.

Sends the prompt bytes from the fixed prompt files to /v1/completions (no server-side template, so the bytes
are the same for both checksets), streams the reply, and appends one JSON line per item to --out. Resumable:
an item whose id is already in --out with no error is skipped, so a dry run of the first 20 items is reused by
the full run and a dropped connection costs one item.

  python quality_client.py --base http://127.0.0.1:8888 --model MODEL --arm A \
      --prompts ../../work/QualityCmp/prompts/prompts_gsm8k.jsonl \
      --out ../../work/QualityCmp/raw/A/gsm8k.jsonl --concurrency 8 [--limit 20]

Every body carries temperature 0 and no sampling parameters (no seed, no top-p/top-k), so the two arms send
the same body apart from the served model id.
"""

import argparse
import hashlib
import json
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CLIENT_SHA = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
DONE = threading.Event()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class Collector:
    """Accumulate SSE chunks: text, timestamps, usage, finish_reason, error frames."""

    def __init__(self, start: float):
        self.start = start
        self.text: list[str] = []
        self.first: float | None = None
        self.last: float | None = None
        self.usage: dict | None = None
        self.finish: str | None = None
        self.error: str | None = None
        self.chunks = 0

    def feed(self, payload: dict) -> None:
        if payload.get("error"):
            self.error = json.dumps(payload["error"])[:400]
        if payload.get("usage"):
            self.usage = payload["usage"]
        for choice in payload.get("choices") or []:
            piece = choice.get("text")
            if piece is None:
                piece = (choice.get("delta") or {}).get("content")
            if piece:
                now = time.perf_counter()
                self.first = now if self.first is None else self.first
                self.last = now
                self.text.append(piece)
                self.chunks += 1
            if choice.get("finish_reason"):
                self.finish = choice["finish_reason"]


def post(base: str, body: dict, timeout: float) -> tuple[int, str]:
    request = urllib.request.Request(
        base.rstrip("/") + "/v1/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8", "replace")


def stream_item(base: str, model: str, item: dict, seed: int | None, timeout: float,
                use_stop: bool = True) -> dict:
    body = {
        "model": model,
        "prompt": item["prompt"],
        "max_tokens": int(item["max_tokens"]),
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if use_stop and item.get("stop"):
        body["stop"] = item["stop"]
    if seed is not None:
        body["seed"] = seed
    request = urllib.request.Request(
        base.rstrip("/") + "/v1/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
    )
    record = {"id": item["id"], "bench": item["bench"], "arm": item["arm"], "base": base, "model": model,
              "prompt_sha256": sha256_text(item["prompt"]), "body_sha256": sha256_text(json.dumps(body, sort_keys=True)),
              "max_tokens": body["max_tokens"], "stop": body.get("stop"), "error": None, "http": None,
              "text": "", "finish_reason": None, "usage": None, "ttft_s": None, "decode_s": None,
              "decode_tps": None, "completion_tokens": None, "prompt_tokens": None, "wall_s": None,
              "chunks": 0, "attempts": 0}
    collector = None
    start = time.perf_counter()
    for attempt in range(4):
        record["attempts"] = attempt + 1
        collector = Collector(start)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                record["http"] = response.status
                if "event-stream" not in (response.headers.get("Content-Type") or ""):
                    document = json.loads(response.read().decode("utf-8", "replace"))
                    if isinstance(document, dict) and document.get("error"):
                        collector.error = json.dumps(document["error"])[:400]
                    for choice in (document or {}).get("choices") or []:
                        piece = choice.get("text") or (choice.get("message") or {}).get("content") or ""
                        if piece:
                            now = time.perf_counter()
                            collector.first = now if collector.first is None else collector.first
                            collector.last = now
                            collector.text.append(piece)
                            collector.chunks += 1
                        if choice.get("finish_reason"):
                            collector.finish = choice["finish_reason"]
                    collector.usage = (document or {}).get("usage") or collector.usage
                    break
                for raw in response:
                    line = raw.decode("utf-8", "replace").strip()
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        collector.feed(json.loads(payload))
                    except json.JSONDecodeError:
                        collector.error = f"bad frame: {payload[:120]}"
            break
        except urllib.error.HTTPError as error:
            body_text = error.read().decode("utf-8", "replace")[:400]
            if error.code == 400 and "seed" in body_text and seed is not None:
                record.update({"seed_rejected": True, "error": body_text, "http": 400,
                               "text": "", "text_sha256": sha256_text(""), "wall_s": round(time.perf_counter() - start, 4)})
                return record
            record["error"] = f"HTTP {error.code}: {body_text}"
            if error.code not in (429, 500, 502, 503, 504):
                break
        except (urllib.error.URLError, OSError, TimeoutError) as error:
            record["error"] = f"{type(error).__name__}: {error}"[:400]
        if attempt < 3:
            time.sleep(1.5 * (attempt + 1))
    end = time.perf_counter()
    text = "".join(collector.text) if collector else ""
    usage = collector.usage or {}
    completion_tokens = usage.get("completion_tokens")
    prompt_tokens = usage.get("prompt_tokens")
    first, last = (collector.first, collector.last) if collector else (None, None)
    chunks = collector.chunks if collector else 0
    tokens_source = "usage"
    if completion_tokens is None:
        completion_tokens = chunks or None      # each SSE frame carries one sampled token on this engine
        tokens_source = "chunks"
    record.update({
        "text": text, "text_sha256": sha256_text(text), "finish_reason": collector.finish if collector else None,
        "usage": usage or None, "chunks": chunks, "tokens_source": tokens_source,
        "completion_tokens": completion_tokens, "prompt_tokens": prompt_tokens,
        "ttft_s": round(first - start, 4) if first else None,
        "decode_s": round(last - first, 4) if first and last else None,
        "decode_tps": round((completion_tokens - 1) / (last - first), 2)
        if completion_tokens and completion_tokens > 1 and first and last and last > first else None,
        "wall_s": round(end - start, 4),
    })
    if collector and collector.error:
        record["error"] = (record["error"] or "") + f" stream: {collector.error}"
    if not text and not record["error"]:
        record["error"] = "empty reply"
    return record


def load_prompts(path: Path, bench: str, arm: str) -> list[dict]:
    items = []
    with path.open(encoding="utf-8") as source:
        for line in source:
            row = json.loads(line)
            items.append({**row, "bench": bench, "arm": arm})
    return items


def done_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    done = set()
    with path.open(encoding="utf-8") as source:
        for line in source:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not row.get("error") and row.get("text"):
                done.add(row["id"])
    return done


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8888")
    parser.add_argument("--model", required=True)
    parser.add_argument("--arm", required=True)
    parser.add_argument("--bench", required=True)
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--out", default=None)
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0, help="run only this many missing items")
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--seed", type=int, default=None,
                        help="omitted by default: greedy decoding needs no seed, and no seed keeps the two bodies identical")
    parser.add_argument("--drop-seed", action="store_true")
    parser.add_argument("--no-stop", action="store_true", help="omit the stop field (for a serve that rejects it)")
    parser.add_argument("--probe-stop", action="store_true",
                        help="send one 8-token request with the stop field; exit 0 when the serve accepts it")
    parser.add_argument("--order", default="as-is", choices=("as-is", "shuffle"),
                        help="shuffle measures differently but must be the same for both arms")
    args = parser.parse_args()
    if not args.probe_stop and not args.out:
        parser.error("--out is required")

    if args.probe_stop:
        first = json.loads(Path(args.prompts).read_text(encoding="utf-8").splitlines()[0])
        first.update({"bench": args.bench, "arm": args.arm, "max_tokens": 8})
        probe = stream_item(args.base, args.model, first, None, args.timeout, use_stop=True)
        print(f"PROBE stop http={probe.get('http')} error={str(probe.get('error'))[:200]} "
              f"text={(probe.get('text') or '')[:60]!r}")
        sys.exit(0 if probe.get("http") == 200 and not probe.get("error") else 1)

    items = load_prompts(Path(args.prompts), args.bench, args.arm)
    if args.order == "shuffle":
        random.Random(20261118).shuffle(items)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    already = done_ids(out)
    todo = [item for item in items if item["id"] not in already]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{args.bench} arm {args.arm}: {len(items)} items, {len(already)} done, {len(todo)} to run "
          f"at concurrency {args.concurrency}", flush=True)
    if not todo:
        return

    seed = None if args.drop_seed else args.seed
    started = time.time()
    written = 0
    failures = 0
    lock = threading.Lock()

    def work(item: dict) -> dict:
        nonlocal written, failures
        try:
            record = stream_item(args.base, args.model, item, seed, args.timeout, use_stop=not args.no_stop)
        except Exception as error:                      # one item's failure must never abort the benchmark
            record = {"id": item["id"], "bench": item["bench"], "arm": item["arm"], "base": args.base,
                      "model": args.model, "error": f"{type(error).__name__}: {error}"[:400], "text": "",
                      "attempts": 0, "completion_tokens": None, "finish_reason": None}
        with lock:
            with out.open("a", encoding="utf-8", newline="\n") as sink:
                sink.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
            written += 1
            if record["error"]:
                failures += 1
            if written % 25 == 0 or written == len(todo):
                elapsed = time.time() - started
                rate = written / elapsed if elapsed else 0
                print(f"  {written}/{len(todo)} written, {failures} failed, {rate:.2f} items/s, "
                      f"eta {(len(todo) - written) / rate / 60:.1f} min" if rate else f"  {written}/{len(todo)}",
                      flush=True)
        return record

    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        results = list(pool.map(work, todo))
    rejected = [row for row in results if row.get("seed_rejected")]
    meta = {
        "bench": args.bench, "arm": args.arm, "base": args.base, "model": args.model,
        "concurrency": args.concurrency, "seed": seed, "client_sha256": CLIENT_SHA,
        "prompts_file": str(args.prompts), "started": started, "ended": time.time(),
        "items_total": len(items), "items_run": len(todo), "failed": failures,
        "completion_tokens": sum(row["completion_tokens"] or 0 for row in results),
        "seed_rejected": bool(rejected),
    }
    (out.parent / f"{args.bench}.meta.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n",
                                                       encoding="utf-8")
    print(f"{args.bench} arm {args.arm}: done, {failures} failed of {len(todo)}; "
          f"{meta['completion_tokens']} completion tokens", flush=True)
    if rejected:
        print("SEED REJECTED: rerun both arms with --drop-seed", flush=True)
        sys.exit(3)
    if failures:
        sys.exit(4)


if __name__ == "__main__":
    main()
