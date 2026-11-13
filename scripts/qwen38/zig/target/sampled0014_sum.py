#!/usr/bin/env python3
"""Tables for a sampled0014.sh run: decode tok/s per arm from upstream's clients, each PR arm against the mean of the
two main arms, and the drafter on against "draft": false inside every arm.

bench_concurrent's aggregate tok/s (median of 3 reps) for code and chat at 1, 2 and 4 streams, drafter on and off,
temperatures 1.0 and 0; bench_openai's one-stream decode_tps median at 1.0. A PR cell counts as slower than main when
it is below both main arms (outside the main-vs-main-again spread). A drafter-on cell counts as slower than drafts off
when its aggregate is below the same boot's "draft": false aggregate for the same prompt, temperature and streams.

  python3 sampled0014_sum.py RUN_DIR OUT.md
"""

import json
import sys
from pathlib import Path

ARMS = {"main": "main", "pr-default": "PR, unset", "pr-mxfp8": "PR, mxfp8", "main-again": "main again"}
PR_ARMS = ("pr-default", "pr-mxfp8")
RUNS = {("on", 1.0): "on_t1", ("off", 1.0): "off_t1", ("off", 0.0): "off_t0", ("on", 0.0): "on_t0"}
TEMPS = (1.0, 0.0)
PROMPTS = ("code", "chat")
LEVELS = (1, 2, 4)


def load(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def gather(run: Path) -> dict:
    """{arm: {(draft, temperature): {(prompt, streams): cell}, "openai": rows, "drafts": report}}"""
    data = {}
    for arm in ARMS:
        got = {"openai": load(run / arm / "decode_t1.json") or [], "drafts": load(run / arm / "drafts.json") or {}}
        for key, name in RUNS.items():
            doc = load(run / arm / f"{name}.json") or {}
            got[key] = {(c["prompt"], c["streams"]): c for c in doc.get("cells", []) if c.get("temperature") == key[1]}
        data[arm] = got
    return data


def num(v) -> str:
    return "-" if v is None else f"{v:.1f}"


def table(head: list[str], rows: list[list[str]]) -> list[str]:
    return ["| " + " | ".join(head) + " |", "|" + "---|" * len(head), *("| " + " | ".join(r) + " |" for r in rows)]


def versus_main(values: dict, slow: list, what: str) -> list[str]:
    """The main arms' spread in % of their mean, then each PR arm's delta in % of that mean."""
    a, b = values.get("main"), values.get("main-again")
    if not a or not b:
        return ["-"] + ["-" for _ in PR_ARMS]
    mean = (a + b) / 2
    cols = [f"{abs(a - b) / mean * 100:.1f}%"]
    for arm in PR_ARMS:
        v = values.get(arm)
        if not v:
            cols.append("-")
            continue
        below = v < min(a, b)
        cols.append(f"{(v - mean) / mean * 100:+.1f}%" + (" below both" if below else ""))
        if below:
            slow.append(f"{what}: {ARMS[arm]} {v:.1f} against main {a:.1f} and {b:.1f}")
    return cols


def concurrent_rows(data: dict, draft: str, slow: list) -> list[str]:
    head = ["temperature", "prompt", "streams", *ARMS.values(), "main spread", *(f"{ARMS[a]} vs main" for a in PR_ARMS)]
    rows = []
    for t in TEMPS:
        for prompt in PROMPTS:
            for n in LEVELS:
                values = {}
                for arm in ARMS:
                    c = data[arm][(draft, t)].get((prompt, n))
                    values[arm] = c["aggregate_tps"] if c else None
                what = f"drafter {draft}, temperature {t:g}, {prompt}, {n} streams"
                rows.append([f"{t:g}", prompt, str(n), *(num(values[a]) for a in ARMS), *versus_main(values, slow, what)])
    return table(head, rows)


def openai_rows(data: dict, slow: list) -> list[str]:
    """bench_openai's own prompt names (fibonacci-raw, gpu-chat-no-think), in main's order."""
    head = ["prompt", *ARMS.values(), "main spread", *(f"{ARMS[a]} vs main" for a in PR_ARMS)]
    rows = []
    for prompt in [r.get("prompt") for r in data["main"]["openai"] if r.get("temperature") == 1.0]:
        values = {}
        for arm in ARMS:
            row = next((r for r in data[arm]["openai"] if r.get("prompt") == prompt and r.get("temperature") == 1.0), None)
            values[arm] = row.get("decode_tps_median") if row else None
        rows.append([prompt, *(num(values[a]) for a in ARMS),
                     *versus_main(values, slow, f"bench_openai, temperature 1.0, {prompt}")])
    return table(head, rows)


def ratio_rows(data: dict, slower: list) -> list[str]:
    head = ["temperature", "prompt", "streams", *(f"{v}: on / off" for v in ARMS.values())]
    rows = []
    for t in TEMPS:
        for prompt in PROMPTS:
            for n in LEVELS:
                cols = [f"{t:g}", prompt, str(n)]
                for arm in ARMS:
                    on, off = data[arm][("on", t)].get((prompt, n)), data[arm][("off", t)].get((prompt, n))
                    if not on or not off or not off["aggregate_tps"]:
                        cols.append("-")
                        continue
                    r = on["aggregate_tps"] / off["aggregate_tps"]
                    cols.append(f"{on['aggregate_tps']:.1f} / {off['aggregate_tps']:.1f} = {r:.2f}x"
                                + (" slower" if r < 1 else ""))
                    if r < 1:
                        slower.append(f"{ARMS[arm]}, temperature {t:g}, {prompt}, {n} streams: drafter on "
                                      f"{on['aggregate_tps']:.1f} against off {off['aggregate_tps']:.1f}")
                rows.append(cols)
    return table(head, rows)


def check_rows(data: dict) -> list[str]:
    head = ["arm", "run", "concurrent == alone", "alone == serial", "failed", "unmeasured", "tokens a chunk (pooled)"]
    rows = []
    for arm in ARMS:
        for key, name in RUNS.items():
            cells = list(data[arm][key].values())
            if not cells:
                rows.append([ARMS[arm], name, "missing", "", "", "", ""])
                continue
            alone = [sum((c.get("alone") or {}).get(k, 0) for c in cells) for k in ("equal", "unequal", "failed")]
            widest = [c for c in cells if c["streams"] == max(LEVELS)]
            serial = [sum((c.get("serial") or {}).get(k, 0) for c in widest) for k in ("equal", "unequal", "failed")]
            chunk = sorted(c["pooled"]["tokens_per_chunk"] for c in cells
                           if (c.get("pooled") or {}).get("tokens_per_chunk") is not None)
            rows.append([ARMS[arm], name, f"{alone[0]}/{sum(alone)}", f"{serial[0]}/{sum(serial)}",
                         str(sum(c["failed"] for c in cells)), str(sum(c["unmeasured"] for c in cells)),
                         f"{chunk[0]:.2f}-{chunk[-1]:.2f}" if chunk else "-"])
    out = table(head, rows)
    head = ["arm", "drafted == \"draft\": false", "drafted count of the \"draft\": false replies",
            "accepted a drafted reply"]
    rows = []
    for arm in ARMS:
        got = data[arm]["drafts"].get("rows", [])
        plain = sorted({str((r.get("plain") or {}).get("drafted")) for r in got})
        accepted = [a for a in ((r.get("drafted") or {}).get("accepted") for r in got) if isinstance(a, int)]
        rows.append([ARMS[arm], f"{sum(1 for r in got if r.get('equal'))}/{len(got)}", ", ".join(plain) or "-",
                     f"{min(accepted)}-{max(accepted)}" if accepted else "-"])
    return out + ["", *table(head, rows)]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    run, out = Path(sys.argv[1]), Path(sys.argv[2])
    data = gather(run)
    slow: list[str] = []
    slower: list[str] = []
    lines = ["Decode with the drafter on, bench_concurrent aggregate tok/s (median of 3 reps):", "",
             *concurrent_rows(data, "on", slow), "",
             "Decode with \"draft\": false on every request (bench_nodraft.py, the same client), aggregate tok/s:", "",
             *concurrent_rows(data, "off", slow), "",
             "One stream at temperature 1.0, bench_openai decode_tps (median of 3 seeds):", "",
             *openai_rows(data, slow), "",
             "Drafter on against \"draft\": false in the same boot, aggregate tok/s (on / off = ratio):", "",
             *ratio_rows(data, slower), "",
             "Checks (bench_concurrent's own token_sha256 comparisons; served_exactness.py drafts at 64 tokens):", "",
             *check_rows(data), "",
             f"PR cells below both main arms: {len(slow)}", *(f"- {s}" for s in slow), "",
             f"Drafter-on cells slower than \"draft\": false: {len(slower)}", *(f"- {s}" for s in slower)]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"PR cells below both main arms {len(slow)}; drafter-on cells slower than off {len(slower)}")


if __name__ == "__main__":
    main()
