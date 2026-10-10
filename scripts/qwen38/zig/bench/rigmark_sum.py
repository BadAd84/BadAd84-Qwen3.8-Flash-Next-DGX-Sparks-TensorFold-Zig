#!/usr/bin/env python3
"""rigmark_sum.py: RigMark receipts (github.com/alexellis/rigmark, protocol 1.3) as our harness summaries (the Zig
serve on spark6; ported from glm5.3-flash-dev scripts/glm53/v110/rigmark_sum.py, same format).

  rigmark_sum.py line <receipt.json>    one line, "summary {json}": the receipt's headline numbers (rigmark_run.sh
                                         prints it; the harness logs carry it, so a summary needs no receipt file)
  rigmark_sum.py report <a.txt> <b.txt> the RigMark section for two arms' RIGMARK lines (the first is the reference)

As a module (zab_rm_sum.py): ``collect(lines, group)`` reads "RIGMARK <arm> ..." lines (the arm's summary, receipt and
exit lines) and ``section(found, errors, order, ref)`` returns (lines, error count) of a table of the arm kinds: per
receipt the median of each workload's runs (decode estimate and time to last output), its basic output gates, cold /
immediate-replay prefill (tok/s at each depth, and whether the server's cache usage verified the cold sample), the
C1-C4 aggregate; per kind the mean over its receipts; the change against ``ref``. A receipt with an error, a run that
did not exit 0, or receipts that are not one matched sweep (comparison ID, protocol, RigMark revision, extra body
differing) count as errors."""
import json
import sys
from collections import defaultdict

WORKLOADS = ("code", "prose", "structured")


def med(block, key="median"):
    return block.get(key) if isinstance(block, dict) else None


def headline(r: dict) -> dict:
    """The numbers our summaries read, from a RigMark result (``bench.py``'s JSON)."""

    out = {"label": r.get("run", {}).get("label"), "comparison_id": r.get("run", {}).get("comparison_id"),
           "protocol": r.get("protocol", {}).get("version"),
           "revision": str(r.get("protocol", {}).get("repository_revision", ""))[:12],
           "dirty": r.get("protocol", {}).get("repository_dirty"),
           "extra_body": r.get("settings", {}).get("extra_body"),
           "image": (r.get("run", {}).get("appliance") or {}).get("serving_image"),
           "error": r.get("error"), "decode": {}, "prefill": {}, "concurrency": {}}
    for name in WORKLOADS:
        w = (r.get("decode") or {}).get(name)
        if not w:
            continue
        gate = w.get("completion_gate") or {}
        out["decode"][name] = {"tps": med(w.get("decode_tokens_per_second")),
                               "pooled": w.get("pooled_decode_tokens_per_second"),
                               "last_s": med(w.get("time_to_last_output_seconds")),
                               "ttft_s": med(w.get("ttft_seconds")),
                               "gate": f"{gate.get('passed', 0)}/{gate.get('total', 0)}"}
    for depth, p in (r.get("prefill") or {}).items():
        cold, warm = p.get("cold") or {}, p.get("warm_replay") or {}
        cached = [row.get("cached_prompt_tokens") for row in cold.get("runs") or []]
        replay = [row.get("cached_prompt_tokens") for row in warm.get("runs") or []]
        out["prefill"][depth] = {
            "cold_tps": med(cold.get("effective_prefill_tokens_per_second")), "cold_ttft_s": med(cold.get("ttft_seconds")),
            "replay_tps": med(warm.get("effective_prefill_tokens_per_second")),
            "replay_ttft_s": med(warm.get("ttft_seconds")),
            # RigMark refuses a cold sample with cached tokens; None: the server reported no cache usage
            "cold_verified": bool(cached) and all(c == 0 for c in cached),
            "replay_cached_min": min((c for c in replay if c is not None), default=None)}
    for level, c in (r.get("concurrency") or {}).items():
        streams = [s for rnd in c.get("rounds") or [] for s in rnd.get("streams") or []]
        out["concurrency"][level] = {"agg_tps": med(c.get("aggregate_end_to_end_tokens_per_second")),
                                     "stops": f"{sum(s.get('finish_reason') == 'stop' for s in streams)}/{len(streams)}"}
    return out


def collect(lines, group=lambda arm: arm):
    """{group: [headline, ...]}, [error text, ...], [groups in order of appearance] from "RIGMARK <arm> ..." lines."""

    found, errors, order, pending = defaultdict(list), [], [], {}
    for line in lines:
        p = line.split(None, 3)
        if len(p) < 3 or p[0] != "RIGMARK":
            continue
        arm, tag, rest = p[1], p[2], p[3] if len(p) > 3 else ""
        g = group(arm)
        if g not in order:
            order.append(g)
        if tag == "summary":
            try:
                h = json.loads(rest)
            except ValueError:
                errors.append(f"{arm}: unreadable summary")
                continue
            found[g].append(h)
            pending[arm] = h
            if h.get("error"):
                errors.append(f"{arm}: RigMark stopped: {h['error']}")
        elif tag == "exit":
            if rest.strip() != "0":
                errors.append(f"{arm}: rigmark_run.sh exit {rest.strip()}")
            if arm not in pending:
                errors.append(f"{arm}: no RigMark summary")
            pending.pop(arm, None)
    return found, errors, order


def _fmt(v, nd=1):
    return "-" if v is None else f"{v:,.{nd}f}"


def section(found, errors, order, ref=None):
    out = []
    every = [h for g in order for h in found.get(g, [])]
    if not every:
        lines = ["RigMark: no receipts" + ("" if errors else " (no RIGMARK lines: the phase was off)")]
        return lines + [f"RigMark ERROR {e}" for e in errors], len(errors)
    errors = list(errors)
    for key in ("comparison_id", "protocol", "revision", "extra_body"):
        seen = {json.dumps(h.get(key), sort_keys=True) for h in every}
        if len(seen) > 1:
            errors.append(f"not one matched sweep: {key} differs ({' / '.join(sorted(seen))})")
    h0 = every[0]
    dirty = "dirty" if any(h.get("dirty") for h in every) else "clean"
    out.append(f"RigMark (protocol {h0.get('protocol')}, git {h0.get('revision')} {dirty}, comparison "
               f"{h0.get('comparison_id')}, extra body {json.dumps(h0.get('extra_body'), sort_keys=True)}; per arm "
               f"kind: mean of the receipts' medians, n receipts)")
    rows = []
    for name in WORKLOADS:
        rows.append((f"{name} decode tok/s", lambda h, n=name: h["decode"].get(n, {}).get("tps"), 1))
        rows.append((f"{name} last output s (lower)", lambda h, n=name: h["decode"].get(n, {}).get("last_s"), 1))
        rows.append((f"{name} ttft s (lower)", lambda h, n=name: h["decode"].get(n, {}).get("ttft_s"), 2))
    depths = sorted({d for h in every for d in h["prefill"]}, key=int)
    for d in depths:
        k = f"{int(d) // 1024}K" if int(d) % 1024 == 0 else d
        rows.append((f"prefill {k} cold tok/s", lambda h, d=d: h["prefill"].get(d, {}).get("cold_tps"), 0))
        rows.append((f"prefill {k} replay tok/s", lambda h, d=d: h["prefill"].get(d, {}).get("replay_tps"), 0))
    for lv in sorted({c for h in every for c in h["concurrency"]}, key=int):
        rows.append((f"C{lv} aggregate tok/s", lambda h, lv=lv: h["concurrency"].get(lv, {}).get("agg_tps"), 1))
    head = f"{'rigmark':34s}" + "".join(f"{g:>16s}" for g in order) + (f"{'change':>10s}" if ref in order else "")
    out.append(head)
    for title, get, nd in rows:
        cells, means = [], {}
        for g in order:
            v = [get(h) for h in found.get(g, [])]
            v = [x for x in v if x is not None]
            means[g] = sum(v) / len(v) if v else None
            cells.append(f"{_fmt(means[g], nd)} (n{len(v)})" if v else "-")
        ch = ""
        if ref in order:
            others = [g for g in order if g != ref]
            if len(others) == 1 and means.get(ref) and means.get(others[0]) is not None:
                ch = f"{(means[others[0]] / means[ref] - 1) * 100:+.1f}%"
        out.append(f"{title:34s}" + "".join(f"{c:>16s}" for c in cells) + f"{ch:>10s}")
    for g in order:
        for h in found.get(g, []):
            gates = " ".join(f"{n} {h['decode'][n]['gate']}" for n in WORKLOADS if n in h["decode"])
            cold = ("verified" if all(p["cold_verified"] for p in h["prefill"].values()) else
                    "UNVERIFIED (no cache usage)") if h["prefill"] else "skipped"
            stops = " ".join(f"C{lv} {c['stops']}" for lv, c in sorted(h["concurrency"].items(), key=lambda x: int(x[0])))
            out.append(f"rigmark {h.get('label')}: gates {gates or '-'}; cold prefill {cold}; normal stops {stops or '-'}"
                       f"; image {h.get('image')}")
    out += [f"RigMark ERROR {e}" for e in errors]
    return out, len(errors)


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "line":
        with open(sys.argv[2]) as f:
            print("summary " + json.dumps(headline(json.load(f)), sort_keys=True, separators=(",", ":")))
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "report":
        lines = []
        for path in sys.argv[2:]:
            with open(path, errors="replace") as f:
                lines += f.readlines()
        found, errors, order = collect(lines)
        out, bad = section(found, errors, order, ref=order[0] if order else None)
        print("\n".join(out))
        return 1 if bad else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
