"""Score the saved A/B replies offline. Every number in the results doc comes from this script.

Reads work/QualityCmp/{data/items_<bench>.jsonl,prompts/prompts_<bench>.jsonl,raw/<arm>/<bench>.jsonl} and
writes work/QualityCmp/scores/summary.json plus a markdown table. Extraction is deliberately simple and
auditable, and the counts of replies it could not parse are reported rather than hidden.

  GSM8K      the number after the last '####', else the last number in the reply
  MMLU-Pro   the last 'answer is X' (X a letter A-J), else the last standalone A-J letter in the last 200 chars
  HumanEval  the reply is executed against the official test code in a subprocess (python -I, 15 s timeout)

  python quality_score.py [--arms A,B] [--benches gsm8k,mmlupro,humaneval]
"""

import argparse
import json
import math
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "work" / "QualityCmp"
Z = 1.959963984540054


def wilson(successes: int, n: int) -> tuple[float, float, float]:
    if n == 0:
        return (0.0, 0.0, 0.0)
    p = successes / n
    denominator = 1 + Z * Z / n
    centre = (p + Z * Z / (2 * n)) / denominator
    half = Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n)) / denominator
    return (p, max(0.0, centre - half), min(1.0, centre + half))


def mcnemar_exact(only_a: int, only_b: int) -> float:
    """Two-sided exact binomial test on the discordant pairs (the exact McNemar test)."""
    n = only_a + only_b
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, k) for k in range(0, min(only_a, only_b) + 1)) / 2 ** n
    return min(1.0, 2 * tail)


NUMBER = re.compile(r"[-+]?\$?\d[\d,]*(?:\.\d+)?")
ANSWER_IS = re.compile(r"answer\s*(?:is|:)\s*\(?\s*([A-J])\b", re.IGNORECASE)
LAST_WORD = re.compile(r"\b([A-J])\b")


def extract_gsm8k(text: str) -> tuple[float | None, str]:
    marker = text.rfind("####")
    window = text[marker + 4:] if marker >= 0 else text
    matches = NUMBER.findall(window.replace("$", " "))
    if not matches:
        matches = NUMBER.findall(text.replace("$", " "))
    if not matches:
        return None, "no number"
    raw = matches[-1].replace(",", "")
    try:
        return float(raw), raw
    except ValueError:
        return None, f"unparsable {raw!r}"


def extract_mmlu(text: str) -> tuple[str | None, str]:
    found = ANSWER_IS.findall(text)
    if found:
        return found[-1].upper(), found[-1]
    tail = text[-200:]
    letters = LAST_WORD.findall(tail)
    if letters:
        return letters[-1].upper(), f"fallback {letters[-1]}"
    return None, "no letter"


def gsm8k_equal(predicted: float | None, gold: str) -> bool:
    try:
        target = float(gold.replace(",", ""))
    except ValueError:
        return False
    if predicted is None:
        return False
    return abs(predicted - target) <= 1e-6 * max(1.0, abs(target))


def strip_fences(text: str) -> tuple[str, bool]:
    stripped = text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        return "\n".join(lines) + "\n", True
    return text, False


def run_humaneval(item: dict, reply: str, timeout: float = 15.0) -> dict:
    code, fenced = strip_fences(reply)
    program = item["prompt"] + code + "\n" + item["test"] + f"\ncheck({item['entry_point']})\n"
    with tempfile.TemporaryDirectory(prefix="he-") as folder:
        script = Path(folder) / "candidate.py"
        script.write_text(program, encoding="utf-8")
        started = time.perf_counter()
        try:
            completed = subprocess.run(
                [sys.executable, "-I", str(script)],
                cwd=folder, capture_output=True, text=True, timeout=timeout,
                env={"SystemRoot": "C:\\Windows", "PATH": "", "PYTHONIOENCODING": "utf-8"},
            )
            passed = completed.returncode == 0
            detail = "ok" if passed else (completed.stderr.strip().splitlines() or ["exit"])[-1][:200]
        except subprocess.TimeoutExpired:
            passed = False
            detail = f"timeout {timeout}s"
        except OSError as error:
            passed = False
            detail = f"oserror {error}"
        return {"passed": passed, "detail": detail, "fence_stripped": fenced,
                "seconds": round(time.perf_counter() - started, 2)}


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    if not path.exists():
        return rows
    with path.open(encoding="utf-8") as source:
        for line in source:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return rows


def latest_by_id(path: Path) -> dict[str, dict]:
    """Later lines win, so a resumed run's retried item supersedes its failed first attempt."""
    rows = {}
    for row in load_jsonl(path):
        rows[row["id"]] = row
    return rows


def score_benchmark(bench: str, arms: list[str], concurrency: int, raw: Path) -> dict:
    items = {row["id"]: row for row in load_jsonl(WORK / "data" / f"items_{bench}.jsonl")}
    for row in load_jsonl(WORK / "prompts" / f"prompts_{bench}.jsonl"):
        if row["id"] in items:
            items[row["id"]]["prompt"] = row["prompt"]
    replies = {arm: latest_by_id(raw / arm / f"{bench}.jsonl") for arm in arms}

    outcomes: dict[str, dict[str, dict]] = {arm: {} for arm in arms}
    extract_notes = {arm: {"unparsed": 0, "missing": 0, "truncated": 0, "errors": 0, "fence_stripped": 0,
                           "completion_tokens": [], "decode_tps": [], "wall": [], "prompt_tokens": [],
                           "timeouts": 0, "completed": []} for arm in arms}
    humaneval_tasks = []
    for arm in arms:
        for item_id, item in items.items():
            reply = replies[arm].get(item_id)
            notes = extract_notes[arm]
            if reply is None or reply.get("error") or not reply.get("text"):
                notes["missing"] += 1
                if reply is not None and reply.get("error"):
                    notes["errors"] += 1
                outcomes[arm][item_id] = {"correct": False, "scored": False}
                continue
            if reply.get("finish_reason") == "length":
                notes["truncated"] += 1
            if reply.get("completion_tokens"):
                notes["completion_tokens"].append(reply["completion_tokens"])
            if reply.get("prompt_tokens"):
                notes["prompt_tokens"].append(reply["prompt_tokens"])
            if reply.get("decode_tps"):
                notes["decode_tps"].append(reply["decode_tps"])
            if reply.get("wall_s"):
                notes["wall"].append(reply["wall_s"])
            text = reply["text"]
            if bench == "gsm8k":
                predicted, detail = extract_gsm8k(text)
                correct = gsm8k_equal(predicted, item["gold"])
                if predicted is None:
                    notes["unparsed"] += 1
                outcomes[arm][item_id] = {"correct": correct, "scored": True, "detail": detail}
            elif bench == "mmlupro":
                predicted, detail = extract_mmlu(text)
                correct = predicted == item["gold"]
                if predicted is None:
                    notes["unparsed"] += 1
                outcomes[arm][item_id] = {"correct": correct, "scored": True, "detail": detail}
            else:
                humaneval_tasks.append((arm, item_id, item, text))
                outcomes[arm][item_id] = {"correct": False, "scored": True, "detail": "pending"}
            if reply.get("finish_reason") != "length":
                notes["completed"].append({"id": item_id})

    if humaneval_tasks:
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = [(arm, item_id, pool.submit(run_humaneval, item, text))
                       for arm, item_id, item, text in humaneval_tasks]
            for arm, item_id, future in futures:
                result = future.result()
                outcomes[arm][item_id].update({"correct": result["passed"], "detail": result["detail"]})
                if result["fence_stripped"]:
                    extract_notes[arm]["fence_stripped"] += 1
                if result["detail"].startswith("timeout"):
                    extract_notes[arm]["timeouts"] += 1

    # a reply counts as completed when the serve stopped it itself (not finish_reason == "length")
    for arm in arms:
        completed_ids = {row["id"] for row in extract_notes[arm]["completed"]}
        for item_id, outcome in outcomes[arm].items():
            outcome["completed"] = item_id in completed_ids and outcome["scored"]

    summary = {"bench": bench, "items": len(items), "arms": {}}
    for arm in arms:
        scored_ids = [item_id for item_id in items if outcomes[arm][item_id]["scored"]]
        correct = sum(1 for item_id in scored_ids if outcomes[arm][item_id]["correct"])
        p, low, high = wilson(correct, len(scored_ids))
        completed_ids = [item_id for item_id in scored_ids if outcomes[arm][item_id].get("completed")]
        correct_completed = sum(1 for item_id in completed_ids if outcomes[arm][item_id]["correct"])
        pc, lowc, highc = wilson(correct_completed, len(completed_ids))
        notes = extract_notes[arm]
        summary["arms"][arm] = {
            "n_items": len(items), "n_scored": len(scored_ids), "correct": correct,
            "accuracy": round(p, 4), "wilson_low": round(low, 4), "wilson_high": round(high, 4),
            "n_completed": len(completed_ids), "correct_completed": correct_completed,
            "accuracy_completed": round(pc, 4), "wilson_completed_low": round(lowc, 4),
            "wilson_completed_high": round(highc, 4),
            "unparsed": notes["unparsed"], "missing": notes["missing"], "errors": notes["errors"],
            "truncated": notes["truncated"], "timeouts": notes["timeouts"], "fence_stripped": notes["fence_stripped"],
            "mean_completion_tokens": round(sum(notes["completion_tokens"]) / len(notes["completion_tokens"]), 1)
            if notes["completion_tokens"] else None,
            "mean_prompt_tokens": round(sum(notes["prompt_tokens"]) / len(notes["prompt_tokens"]), 1)
            if notes["prompt_tokens"] else None,
            "mean_decode_tps": round(sum(notes["decode_tps"]) / len(notes["decode_tps"]), 2)
            if notes["decode_tps"] else None,
            "median_decode_tps": round(sorted(notes["decode_tps"])[len(notes["decode_tps"]) // 2], 2)
            if notes["decode_tps"] else None,
            "mean_wall_s": round(sum(notes["wall"]) / len(notes["wall"]), 2) if notes["wall"] else None,
        }

    if len(arms) == 2:
        a, b = arms
        paired = [item_id for item_id in items
                  if outcomes[a][item_id]["scored"] and outcomes[b][item_id]["scored"]]
        only_a = sum(1 for item_id in paired if outcomes[a][item_id]["correct"] and not outcomes[b][item_id]["correct"])
        only_b = sum(1 for item_id in paired if outcomes[b][item_id]["correct"] and not outcomes[a][item_id]["correct"])
        both = sum(1 for item_id in paired if outcomes[a][item_id]["correct"] and outcomes[b][item_id]["correct"])
        p_difference = (summary["arms"][b]["correct"] - summary["arms"][a]["correct"]) / summary["arms"][a]["n_scored"] \
            if summary["arms"][a]["n_scored"] else 0.0
        paired_completed = [item_id for item_id in paired
                            if outcomes[a][item_id].get("completed") and outcomes[b][item_id].get("completed")]
        only_a_c = sum(1 for item_id in paired_completed
                       if outcomes[a][item_id]["correct"] and not outcomes[b][item_id]["correct"])
        only_b_c = sum(1 for item_id in paired_completed
                       if outcomes[b][item_id]["correct"] and not outcomes[a][item_id]["correct"])
        summary["paired"] = {
            "n_paired_completed": len(paired_completed), "only_a_completed": only_a_c,
            "only_b_completed": only_b_c,
            "difference_pp_completed": round(100 * (only_b_c - only_a_c) / len(paired_completed), 2)
            if paired_completed else None,
            "mcnemar_exact_p_completed": round(mcnemar_exact(only_a_c, only_b_c), 6) if paired_completed else None,
            "n_paired": len(paired), "both_correct": both, "only_a": only_a, "only_b": only_b,
            "difference_pp": round(100 * (only_b - only_a) / len(paired), 2) if paired else None,
            "mcnemar_exact_p": round(mcnemar_exact(only_a, only_b), 6) if paired else None,
            "accuracy_difference_pp": round(100 * p_difference, 2),
            "outcomes": {arm: outcomes[arm] for arm in arms},
        }
    return summary


def markdown(summary: dict, arms: list[str]) -> str:
    a, b = arms
    rows = []
    for entry in summary["benches"]:
        sa, sb = entry["arms"][a], entry["arms"][b]
        paired = entry.get("paired", {})
        rows.append(
            f"| {entry['bench']} | {entry['items']} | {paired.get('n_paired', '?')} | "
            f"{sa['correct']}/{sa['n_scored']} = {100 * sa['accuracy']:.1f}% "
            f"[{100 * sa['wilson_low']:.1f}, {100 * sa['wilson_high']:.1f}] | "
            f"{sb['correct']}/{sb['n_scored']} = {100 * sb['accuracy']:.1f}% "
            f"[{100 * sb['wilson_low']:.1f}, {100 * sb['wilson_high']:.1f}] | "
            f"{paired.get('difference_pp', '?')} | {paired.get('only_a', '?')} | {paired.get('only_b', '?')} | "
            f"{paired.get('mcnemar_exact_p', '?')} | {sa['truncated']}/{sb['truncated']} | "
            f"{sa['mean_completion_tokens']}/{sb['mean_completion_tokens']} | "
            f"{sa['mean_decode_tps']}/{sb['mean_decode_tps']} | "
            f"{sa['missing']}/{sb['missing']} | {sa['unparsed']}/{sb['unparsed']} |")
    header = ("| bench | items | paired | " + a + " acc (95% Wilson) | " + b + " acc (95% Wilson) | "
              "diff pp (" + b + "-" + a + ", paired) | only " + a + " | only " + b + " | McNemar exact p | "
              "trunc " + a + "/" + b + " | mean tok " + a + "/" + b + " | decode tok/s " + a + "/" + b + " | "
              "missing " + a + "/" + b + " | unparsed " + a + "/" + b + " |\n"
              "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    return header + "\n" + "\n".join(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arms", default="A,B")
    parser.add_argument("--benches", default="gsm8k,mmlupro,humaneval")
    parser.add_argument("--concurrency", type=int, default=8)
    parser.add_argument("--raw", default=str(WORK / "raw"))
    parser.add_argument("--out", default=str(WORK / "scores"))
    args = parser.parse_args()
    arms = args.arms.split(",")
    benches = [bench for bench in args.benches.split(",") if bench]

    summary = {"arms": arms, "benches": [], "started": time.time()}
    for bench in benches:
        print(f"scoring {bench} ...", flush=True)
        summary["benches"].append(score_benchmark(bench, arms, args.concurrency, Path(args.raw)))
    summary["ended"] = time.time()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    table = markdown(summary, arms)
    (out / "summary.md").write_text(table + "\n", encoding="utf-8")
    print(table)


if __name__ == "__main__":
    main()
