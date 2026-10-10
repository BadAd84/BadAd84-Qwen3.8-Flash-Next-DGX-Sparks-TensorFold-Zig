"""mutants_ttft.py [--probe ttft.py] [--test test_ttft.py] [--jobs N]: CPU only, loopback only. test_ttft.py must
PASS on ttft.py as it is and FAIL on every mutant below. Each mutant is ttft.py with ONE anchored replacement, written
to a scratch dir under $HOME (an anchor that does not match exactly once is an ERROR, never a pass) and run through
the test with --probe pointing at it. A kill needs the test's non-zero exit AND its FAILED line (a crash of the test
itself is not a kill). Exit 0 only when the unmutated probe passes and every mutant is killed.

Every flagging decision has mutants both ways: NOTCOLD / NOTWARM / NOLOAD never raised, always raised, and (NOTCOLD,
NOTWARM) raised on the other case kind.
Not here, by design: the timestamp of an event taken at its first data line rather than at the blank line that
dispatches it (the server writes both in one write, so no black-box test can tell them apart), and the summary's
p90 / median formatting in run() (the same p90() / med() that collect() / section() use, which are mutated here).
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent

MUTANTS = [
    # what counts as the first token
    ("role-chunk-counted", '        if delta.get("reasoning_content"):\n',
     '        if delta.get("role") or delta.get("reasoning_content"):\n'),
    ("keepalive-counted", '        field, _, value = line.partition(":")',
     '        if line.startswith(":"):\n            return ("message", \'{"type": "content_block_delta", "delta": '
     '{"type": "text_delta", "text": "k"}, "choices": [{"delta": {"content": "k"}}]}\', t)\n'
     '        field, _, value = line.partition(":")'),
    ("reasoning-ignored", '        if delta.get("reasoning_content"):\n', "        if False:\n"),
    ("thinking-delta-ignored", 'if d.get("type") == "thinking_delta" and d.get("thinking"):', "if False:"),
    ("empty-delta-counted", '        if delta.get("content"):', '        if "content" in delta:'),
    ("ping-counted", "    return None                    # ping",
     '    return ("content", "") if kind == "ping" else None  # ping'),
    ("empty-block-start-counted", '        if (obj.get("content_block") or {}).get("type") == "tool_use":',
     "        if True:"),
    ("openai-tool-ignored", '        if delta.get("tool_calls"):', "        if False:"),
    ("anthropic-tool-ignored", '            return ("tool", "")', "            return None"),
    ("t0-after-headers", '            out["admit"] = time.perf_counter() - t0\n',
     '            out["admit"] = time.perf_counter() - t0\n            t0 = time.perf_counter()\n'),
    ("last-token-counted", 'if token is not None and out["ttft"] is None:', "if token is not None:"),
    # the request
    ("thinking-switch-wrong-key", '"chat_template_kwargs": {"enable_thinking": thinking}',
     '"chat_template_kwargs": {"thinking": thinking}'),
    # SSE framing
    ("crlf-not-stripped", '.rstrip("\\n").rstrip("\\r")', '.rstrip("\\n")'),
    ("data-lines-not-joined", '"\\n".join(self.data)', "self.data[-1]"),
    # errors
    ("no-end-accepted", '            out["error"] = "the stream ended without its end event"', "            pass"),
    ("no-token-accepted", '            out["error"] = "the stream ended without a content, reasoning or tool token"',
     "            pass"),
    ("openai-error-event-ignored", '    if "error" in obj:', "    if False:"),
    ("anthropic-error-event-ignored", '    if kind == "error":', "    if False:"),
    ("http-error-swallowed", '        out["error"] = f"HTTP {exc.code}: {exc.read()[:200]!r}"',
     '        out["error"] = None'),
    # the split and the usage
    ("queue-ignored", 'QUEUE_KEYS = ("queue_s", "queued_s", "queue_wait_s", "wait_s")', "QUEUE_KEYS = ()"),
    ("other-keeps-queue", ' - (queue or 0.0) - prefill if prefill', " - prefill if prefill"),
    ("prefill-ignored", "    prefill = stat(stats, PREFILL_KEY)", "    prefill = None"),
    ("prefill-key-glm", 'PREFILL_KEY = "prefill_seconds"', 'PREFILL_KEY = "prefill_s"'),
    ("py-prefill-ignored", "        prefill = stat(stats, PY_PREFILL_KEY)", "        prefill = None"),
    ("server-ttft-key-wrong", 'SERVER_TTFT_KEY = "time_to_first_token"', 'SERVER_TTFT_KEY = "ttft"'),
    ("openai-cached-key", '.get("cached_tokens")', '.get("cached")'),
    ("separate-usage-ignored", '    if obj.get("usage"):', '    if obj.get("usage") and obj.get("choices"):'),
    ("anthropic-prompt-without-cached", 'out["prompt"] = int(u.get("input_tokens") or 0) + cached + int(',
     'out["prompt"] = int(u.get("input_tokens") or 0) + int('),
    # the load and the warm turn
    ("no-wait-per-sample", "                if bg is not None:\n                    bg.ready(args.load_wait)\n", ""),
    ("one-stream-short", "            bg = Load(url, args.api, n_others, ",
     "            bg = Load(url, args.api, n_others - 1, "),
    ("load-never-stops", "                if stop is not None and stop.is_set():\n                    break\n",
     "                pass\n"),
    ("load-errors-dropped", """                self.errors.append(f"stream {i}: {res['error']}")""", "                pass"),
    ("warm-reply-dropped", '"content": "".join(res["text"])}', '"content": "OK"}'),
    ("warm-not-reprimed",
     "                    res = stream(url, args.api, prime_body, args.timeout)     # the previous turn, unmeasured\n",
     '                    res = {"error": None}\n'),
    # flags: each decision never, always, and on the wrong case kind
    ("notcold-never", 'res["cached"] > 0.05 * max(res["prompt"], 1)', 'res["cached"] > 1e18'),
    ("notcold-always", 'res["cached"] > 0.05 * max(res["prompt"], 1)', 'res["cached"] >= 0'),
    ("notcold-any-case", 'if case.startswith("cold") and res["cached"] > ', 'if res["cached"] > '),
    ("notwarm-never", 'res["cached"] < 0.5 * max(res["prompt"], 1)', 'res["cached"] < 0'),
    ("notwarm-always", 'res["cached"] < 0.5 * max(res["prompt"], 1)', 'res["cached"] < 1e18'),
    ("notwarm-any-case", 'if case.startswith("warm") and res["cached"] < ', 'if res["cached"] < '),
    ("noload-never", "                if others < n_others:", "                if False:"),
    ("noload-always", "                if others < n_others:", "                if others <= n_others:"),
    ("flagged-in-median", "                if flags:\n                    flagged[case, load] += 1",
     "                if False:\n                    flagged[case, load] += 1"),
    ("run-exit-0", "    return 1 if errors else 0\n\n\ndef main", "    return 0\n\n\ndef main"),
    # the harness side
    ("collect-keeps-flagged", '        if s["flags"]:\n            excluded[g] += 1',
     '        if False:\n            excluded[g] += 1'),
    ("collect-exit-ignored", '            if rc[1] != "0":', "            if False:"),
    ("p90-is-median", "return s[max(0, math.ceil(0.9 * len(s)) - 1)]", "return s[len(s) // 2]"),
    ("change-inverted", "(m / base - 1) * 100", "(base / m - 1) * 100"),
    ("report-exit-0", "    return 1 if errors else 0\n\n\n# ---- the probe", "    return 0\n\n\n# ---- the probe"),
    ("cases-unordered", "keys = sorted(samples, key=lambda k: (load_key(k[1]), case_key(k[0])))",
     "keys = sorted(samples)"),
]


def run_one(name: str, old: str | None, new: str | None, src: str, test: Path, scratch: Path) -> str:
    d = scratch / name
    d.mkdir()
    text = src
    if old is not None:
        n = src.count(old)
        if n != 1:
            return f"ERROR {name}: anchor matches {n} times"
        text = src.replace(old, new)
    probe = d / "ttft.py"
    probe.write_text(text)
    r = subprocess.run([sys.executable, "-B", str(test), "--probe", str(probe)], capture_output=True, text=True,
                       timeout=900)
    out = r.stdout + r.stderr
    (d / "log.txt").write_text(out)
    if old is None:
        return "unmutated: PASS" if r.returncode == 0 else f"ERROR unmutated: FAILS, exit {r.returncode}\n{out[-1500:]}"
    if r.returncode == 0:
        return f"SURVIVED {name}"
    if "\nFAILED" in out:
        first = next((ln for ln in out.splitlines() if ln.startswith("FAIL ")), "")
        return f"KILLED {name} ({out.count(chr(10) + 'FAIL ')} failures: {first[:110]})"
    return f"ERROR {name}: crashed, exit {r.returncode}: {out.strip().splitlines()[-1:]}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", default=str(HERE.parent / "ttft.py"))
    ap.add_argument("--test", default=str(HERE / "test_ttft.py"))
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    src = Path(a.probe).read_text()
    test = Path(a.test).resolve()
    scratch = Path(tempfile.mkdtemp(prefix="mut-ttft-", dir=Path.home()))
    try:
        with ThreadPoolExecutor(a.jobs) as pool:
            futs = [pool.submit(run_one, "unmutated", None, None, src, test, scratch)]
            futs += [pool.submit(run_one, n, o, w, src, test, scratch) for n, o, w in MUTANTS]
            verdicts = [f.result() for f in futs]
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    print("\n".join(verdicts))
    good = verdicts[0] == "unmutated: PASS" and all(v.startswith("KILLED ") for v in verdicts[1:])
    killed = sum(v.startswith("KILLED ") for v in verdicts[1:])
    print(f"{'ALL KILLED' if good else 'NOT CLEAN'}: {killed} / {len(MUTANTS)} mutants killed")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
