"""Build the fixed prompt files for the A (INT4-AutoRound) against B (FP4-Local) quality comparison.

Downloads the three official datasets at pinned revisions into work/QualityCmp/hf_cache and writes, under
work/QualityCmp/:

  data/items_gsm8k.jsonl     500 test problems drawn with seed 20261118 (of the 1,319), gold answer
  data/items_mmlupro.jsonl   1,000 test questions stratified across the 14 categories, gold letter
  data/items_humaneval.jsonl the 164 test problems, canonical completion prompt and test code
  prompts/prompts_gsm8k.jsonl    one line per item: {"id","prompt","max_tokens","stop"}
  prompts/prompts_mmlupro.jsonl
  prompts/prompts_humaneval.jsonl
  data/manifest.json         revisions, counts, seed, per-file sha256, template hash, render settings

The prompts are rendered ONCE, here, from the checkpoint's own chat template with enable_thinking=false, and
sent verbatim to /v1/completions by the client. That is what makes the bytes identical for both arms: neither
serve renders a template for a completion request, and both checkpoints ship the same template file
(c3cf9e34abf4f9e3..., checked in the manifest by hash).

Not compiled, not run on a GPU: this is dataset preparation on the laptop.
"""

import argparse
import hashlib
import json
import os
import random
import re
import sys
from pathlib import Path

import jinja2

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "work" / "QualityCmp"
os.environ.setdefault("HF_HOME", str(WORK / "hf_cache"))
os.environ.setdefault("HF_DATASETS_CACHE", str(WORK / "hf_cache" / "datasets"))

SEED = 20261118
GSM8K_N = 500
MMLUPRO_N = 1000

REVISIONS = {
    "gsm8k": ("openai/gsm8k", "740312add88f781978c0658806c59bc2815b9866"),
    "mmlupro": ("TIGER-Lab/MMLU-Pro", "b189ec765aa7ed75c8acfea42df31fdae71f97be"),
    "humaneval": ("openai/openai_humaneval", "7dce6050a7d6d172f3cc5c32aa97f52fa1a2e544"),
}

MAX_TOKENS = {"gsm8k": 1024, "mmlupro": 1536, "humaneval": 1024}
STOP = {"gsm8k": ["<|im_end|>"], "mmlupro": ["<|im_end|>"],
        "humaneval": ["\nclass", "\ndef", "\n#", "\nif", "\nprint"]}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def renderer(template_text: str):
    env = jinja2.Environment(undefined=jinja2.StrictUndefined)
    env.globals["raise_exception"] = lambda message: (_ for _ in ()).throw(ValueError(message))

    def render(user_text: str) -> str:
        template = env.from_string(template_text)
        return template.render(
            messages=[{"role": "user", "content": user_text}],
            tools=None,
            add_generation_prompt=True,
            enable_thinking=False,
        )

    return render


def gsm8k(load, render) -> tuple[list[dict], list[dict]]:
    name, revision = REVISIONS["gsm8k"]
    test = load(name, "main", split="test", revision=revision)
    train = load(name, "main", split="train", revision=revision)
    shots = []
    for i in range(8):
        row = train[i]
        shots.append(f"Q: {row['question'].strip()}\nA: {row['answer'].strip()}")
    preamble = "\n\n".join(shots)

    rng = random.Random(SEED)
    order = sorted(range(len(test)), key=lambda i: test[i]["question"])
    picked = sorted(rng.sample(order, GSM8K_N))
    items, prompts = [], []
    for rank, index in enumerate(picked):
        row = test[index]
        question = row["question"].strip()
        gold = row["answer"].strip().split("####")[-1].strip()
        item_id = f"gsm8k-test-{index}"
        question_block = f"{preamble}\n\nQ: {question}\nA:"
        items.append({"id": item_id, "index": index, "gold": gold, "question_sha256": sha256_text(question)})
        prompts.append({"id": item_id, "prompt": render(question_block),
                        "max_tokens": MAX_TOKENS["gsm8k"], "stop": STOP["gsm8k"]})
    return items, prompts


def mmlu_pro(load, render) -> tuple[list[dict], list[dict]]:
    name, revision = REVISIONS["mmlupro"]
    test = load(name, split="test", revision=revision)
    rows = list(test)
    categories = sorted({row["category"] for row in rows})
    by_category = {category: [i for i, row in enumerate(rows) if row["category"] == category] for category in categories}

    total = len(rows)
    exact = {category: MMLUPRO_N * len(indices) / total for category, indices in by_category.items()}
    targets = {category: max(1, int(exact[category])) for category in categories}
    while sum(targets.values()) < MMLUPRO_N:
        category = max(categories, key=lambda c: exact[c] - targets[c])
        targets[category] += 1
    while sum(targets.values()) > MMLUPRO_N:
        category = max((c for c in categories if targets[c] > 1), key=lambda c: targets[c] - exact[c])
        targets[category] -= 1

    rng = random.Random(SEED)
    picked: list[tuple[int, str]] = []
    for category in categories:
        indices = by_category[category]
        picked.extend((i, category) for i in sorted(rng.sample(indices, targets[category])))
    picked.sort()

    items, prompts = [], []
    for index, category in picked:
        row = rows[index]
        options = row["options"]
        letters = "ABCDEFGHIJ"
        lines = [f"{letters[i]}. {option.strip()}" for i, option in enumerate(options)]
        question_text = (
            "Answer the following multiple choice question. Think step by step, then give the final "
            "answer on the last line as: The answer is X. (X is one of the letters A to J.)\n\n"
            f"Question: {row['question'].strip()}\n\n" + "\n".join(lines)
        )
        item_id = f"mmlupro-test-{row['question_id']}"
        items.append({"id": item_id, "index": index, "category": category,
                      "gold": letters[row["answer_index"]],
                      "question_sha256": sha256_text(row["question"].strip())})
        prompts.append({"id": item_id, "prompt": render(question_text),
                        "max_tokens": MAX_TOKENS["mmlupro"], "stop": STOP["mmlupro"]})
    return items, prompts


def humaneval(load, render) -> tuple[list[dict], list[dict]]:
    name, revision = REVISIONS["humaneval"]
    test = load(name, split="test", revision=revision)
    items, prompts = [], []
    for index, row in enumerate(sorted(test, key=lambda r: r["task_id"])):
        item_id = row["task_id"]
        items.append({"id": item_id, "index": index, "entry_point": row["entry_point"],
                      "prompt_sha256": sha256_text(row["prompt"]), "test": row["test"]})
        # The canonical completion prompt: the raw signature and docstring, no chat template.
        prompts.append({"id": item_id, "prompt": row["prompt"],
                        "max_tokens": MAX_TOKENS["humaneval"], "stop": STOP["humaneval"]})
    return items, prompts


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as out:
        for row in rows:
            out.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="re-hash the existing files and compare with the manifest")
    args = parser.parse_args()

    data = WORK / "data"
    prompts_dir = WORK / "prompts"
    manifest_path = data / "manifest.json"

    if args.check:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        bad = []
        for relative, expected in manifest["files"].items():
            actual = sha256_file(ROOT / relative)
            if actual != expected:
                bad.append(f"{relative}: {expected} -> {actual}")
        print("OK all hashes match the manifest" if not bad else "MISMATCH\n" + "\n".join(bad))
        sys.exit(1 if bad else 0)

    from datasets import load_dataset

    template_path = data / "chat_template.jinja"
    template_text = template_path.read_text(encoding="utf-8")
    render = renderer(template_text)

    manifest = {
        "seed": SEED,
        "counts": {"gsm8k": GSM8K_N, "mmlupro": MMLUPRO_N, "humaneval": 164},
        "strategy": {
            "gsm8k": "8-shot chain of thought; 8 fixed train examples (indices 0-7 of openai/gsm8k main train); "
                     "500 of 1,319 test problems drawn by random.Random(20261118).sample over question-sorted indices",
            "mmlupro": "zero-shot chain of thought, final line 'The answer is X'; 1,000 of 12,032 test questions "
                       "stratified across the 14 categories by proportional largest-remainder allocation, sampled "
                       "with random.Random(20261118)",
            "humaneval": "all 164 problems, the canonical completion prompt, official stop sequences, official test code",
        },
        "render": {"template": "data/chat_template.jinja", "enable_thinking": False,
                   "add_generation_prompt": True, "tools": None,
                   "note": "GSM8K and MMLU-Pro prompts are chat-template renders sent to /v1/completions; "
                           "HumanEval prompts are the canonical raw completion prompts"},
        "max_tokens": MAX_TOKENS,
        "stop": STOP,
        "datasets": {key: {"name": name, "revision": revision} for key, (name, revision) in REVISIONS.items()},
        "files": {},
    }

    builders = {"gsm8k": gsm8k, "mmlupro": mmlu_pro, "humaneval": humaneval}
    for key, builder in builders.items():
        print(f"building {key} ...", flush=True)
        items, prompts = builder(load_dataset, render)
        items_path = data / f"items_{key}.jsonl"
        prompts_path = prompts_dir / f"prompts_{key}.jsonl"
        write_jsonl(items_path, items)
        write_jsonl(prompts_path, prompts)
        manifest["files"][str(items_path.relative_to(ROOT))] = sha256_file(items_path)
        manifest["files"][str(prompts_path.relative_to(ROOT))] = sha256_file(prompts_path)
        manifest["files"][str(template_path.relative_to(ROOT))] = sha256_file(template_path)
        print(f"  {len(items)} items, prompts {prompts_path.name}", flush=True)

    manifest["files"][str(Path("work/QualityCmp/data/tokenizer_config_fp4.json"))] = sha256_file(
        data / "tokenizer_config_fp4.json")
    manifest["template_sha256_prefix"] = sha256_file(template_path)[:16]
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"manifest {manifest_path} written", flush=True)


if __name__ == "__main__":
    main()
