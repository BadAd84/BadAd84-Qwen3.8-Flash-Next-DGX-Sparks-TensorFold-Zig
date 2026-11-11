#!/usr/bin/env python3
"""Tests for bench/draft_accounting.py: the /metrics parse, the per-round deltas and ratios, and one end-to-end
run of the instrument against a fake serve that scripts the counters."""
import json, os, subprocess, sys, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)
sys.path.insert(0, BENCH)
import draft_accounting

PROM = """# TYPE mtp_drafted_total counter
mtp_drafted_total{rank="0"} 900
mtp_accepted_total 450
decode_rounds_total 300
"""


PROM_PREFIXED = """# TYPE tensorfold:mtp_drafted_total counter
tensorfold:mtp_drafted_total 111
tensorfold:mtp_accepted_total 66
tensorfold:decode_rounds_total 33
"""


class ParseMetrics(unittest.TestCase):
    def test_the_servers_prefixed_families(self):
        m = draft_accounting.parse_metrics(PROM_PREFIXED)
        self.assertEqual(m["mtp_drafted_total"], 111.0)
        self.assertEqual(m["mtp_accepted_total"], 66.0)
        self.assertEqual(m["decode_rounds_total"], 33.0)

    def test_reads_the_three_counters(self):
        m = draft_accounting.parse_metrics(PROM)
        self.assertEqual(m["mtp_drafted_total"], 900.0)
        self.assertEqual(m["mtp_accepted_total"], 450.0)
        self.assertEqual(m["decode_rounds_total"], 300.0)

    def test_absent_counter_is_none(self):
        m = draft_accounting.parse_metrics("mtp_accepted_total 7\n")
        self.assertIsNone(m["mtp_drafted_total"])
        self.assertEqual(m["mtp_accepted_total"], 7.0)


class Account(unittest.TestCase):
    def m(self, d, a, r):
        return {"mtp_drafted_total": d, "mtp_accepted_total": a, "decode_rounds_total": r}

    def test_deltas_and_ratios(self):
        out = draft_accounting.account(self.m(100, 60, 20), self.m(130, 78, 44), tokens=30, span_s=0.25)
        self.assertEqual((out["rounds"], out["drafted"], out["accepted"]), (24, 30, 18))
        self.assertAlmostEqual(out["acceptance"], 0.6)
        self.assertAlmostEqual(out["tok_per_round"], 1.25)
        self.assertAlmostEqual(out["ms_per_round"], 250 / 24, places=6)

    def test_no_drafts_no_acceptance(self):
        out = draft_accounting.account(self.m(0, 0, 5), self.m(0, 0, 9), tokens=4, span_s=1.0)
        self.assertIsNone(out["acceptance"])
        self.assertAlmostEqual(out["tok_per_round"], 1.0)

    def test_reset_counter_is_none(self):
        out = draft_accounting.account(self.m(50, 20, 9), self.m(2, 1, 1), tokens=4, span_s=1.0)
        self.assertIsNone(out["rounds"])

    def test_serve_without_metrics(self):
        empty = dict.fromkeys(draft_accounting.COUNTERS, None)
        out = draft_accounting.account(empty, empty, tokens=4, span_s=1.0)
        self.assertIsNone(out["acceptance"])
        self.assertIsNone(out["tok_per_round"])


class FakeServe(BaseHTTPRequestHandler):
    tokens = 6
    step = {"mtp_drafted_total": 4, "mtp_accepted_total": 3, "decode_rounds_total": 5}
    polls = 0

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/v1/models":
            body = json.dumps({"data": [{"id": "fake"}]}).encode()
            self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
            return self.wfile.write(body)
        if self.path == "/metrics":
            n = FakeServe.polls; FakeServe.polls += 1
            body = "".join(f"{k} {v * n}\n" for k, v in FakeServe.step.items()).encode()
            self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
            return self.wfile.write(body)
        self.send_error(404)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        for i in range(FakeServe.tokens):
            ev = {"choices": [{"delta": {"content": f"t{i} "}, "finish_reason": None}]}
            self.wfile.write(f"data: {json.dumps(ev)}\n\n".encode())
        self.wfile.write(f"data: {json.dumps({'choices': [], 'usage': {'completion_tokens': FakeServe.tokens}})}\n\n".encode())
        self.wfile.write(f"data: {json.dumps({'choices': [{'delta': {}, 'finish_reason': 'length'}]})}\n\n".encode())
        self.wfile.write(b"data: [DONE]\n\n")


class EndToEnd(unittest.TestCase):
    def test_one_round_carries_the_accounting(self):
        srv = HTTPServer(("127.0.0.1", 0), FakeServe)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        FakeServe.polls = 0
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "rows.jsonl")
            run = subprocess.run([sys.executable, os.path.join(BENCH, "draft_accounting.py"),
                                  str(srv.server_address[1]), "1", "--rounds", "1", "--max-tokens", "6",
                                  "--tag", "t", "--out", out],
                                 capture_output=True, text=True, timeout=120)
            srv.shutdown()
            self.assertEqual(run.returncode, 0, run.stderr)
            row = [json.loads(l) for l in open(out) if json.loads(l).get("round") == 0][0]
            self.assertEqual(row["drafted"], FakeServe.step["mtp_drafted_total"])
            self.assertEqual(row["accepted"], FakeServe.step["mtp_accepted_total"])
            self.assertEqual(row["draft_rounds"], FakeServe.step["decode_rounds_total"])
            self.assertAlmostEqual(row["acceptance"], round(3 / 4, 3))
            self.assertIsNotNone(row["tok_per_round"])


if __name__ == "__main__":
    unittest.main()
