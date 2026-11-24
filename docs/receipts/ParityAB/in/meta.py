#!/usr/bin/env python3
"""meta.py DIR ARM C - one shot's identity file, from the artifacts the driver captured beside it.

Writes DIR/meta.txt, key=value lines, so the summariser never has to re-parse a log's prose for what the shot was:
image tag and id, the engine's own model directory, the container's command, the planned shape and memory, the
boot's health and context, the golden result, the GPU readings the driver recorded, the arm's foreign-traffic
count, the boot wall and, when the driver copied them in, the preflight verdicts for this arm.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def main() -> int:
    d, arm, c = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    meta: dict[str, str] = {"arm": arm, "C": c}

    image = read(d / "image-id.txt").split()
    if len(image) >= 2:
        meta["image_tag"], meta["image_id"] = image[0], image[1]

    try:
        cmd = json.loads(read(d / "cmd.json") or "[]")
    except json.JSONDecodeError:
        cmd = []
    if cmd:
        meta["flags"] = str(sum(1 for t in cmd if isinstance(t, str) and t.startswith("--")))
        if "serve" in cmd:
            rest = cmd[cmd.index("serve") + 1:]
            if rest and not str(rest[0]).startswith("--"):
                meta["model_dir"] = rest[0]
            for flag, key in (("--context", "ctx"), ("--parallel", "parallel"), ("--max-tokens", "max_tokens"),
                              ("--kv-dtype", "kv_dtype"), ("--kv-cache", "kv_cache")):
                if flag in rest:
                    at = rest.index(flag)
                    if at + 1 < len(rest):
                        meta[key] = str(rest[at + 1])
    if not meta.get("model_dir"):
        m = re.search(r"^# model (\S+)$", read(d / "flags-expanded.txt"), re.M)
        if m:
            meta["model_dir"] = m[1]

    env = [ln for ln in read(d / "env.txt").splitlines() if ln.strip()]
    meta["env_names"] = str(len(env))

    health = read(d / "health.json")
    for key, pattern in (("max_batch", r'"max_batch_size":\s*(\d+)'), ("ctx", r'"context":\s*(\d+)')):
        m = re.search(pattern, health)
        if m:
            meta[key] = m[1]

    plan_map = (("plan_streams", "streams at once"), ("plan_seqmem", "sequence memory"),
                ("plan_cache", "prompt cache"), ("plan_pages", "KV page groups"),
                ("plan_vision", "vision:"), ("plan_drafthead", "draft head"), ("plan_int4", "int4 kernels"))
    for line in read(d / "plan.txt").splitlines():
        for key, needle in plan_map:
            if needle in line and key not in meta:
                meta[key] = line.strip()[:400]

    gold = read(d / "gold.txt")
    m = re.search(r"^(\S+): (\d+/\d+ identical to \S+)$", gold, re.M)
    if m:
        meta["gold"] = m[2] if m[2].startswith(("6/6", "5/6", "4/6", "3/6", "2/6", "1/6", "0/6")) else m[2]
        meta["gold_ok"] = "1" if m[2].startswith("6/6") else "0"
    elif "error" in gold.lower():
        meta["gold"] = "ERROR"

    for line in read(d / "gpu.txt").splitlines():
        key, _, value = line.partition(" ")
        meta[f"gpu_{key}"] = value.strip()[:120]

    boot = read(d / "boot_time.txt")
    m = re.search(r"^boot_s ([\d.]+)$", boot, re.M)
    if m:
        meta["boot_s"] = m[1]

    foreign = 0
    for line in read(d / "server.log").splitlines():
        if '"GET /' in line or '"POST /' in line:
            if not re.search(r"\[tensorfold\] 127\.0\.0\.1 ", line):
                foreign += 1
    meta["foreign_lines"] = str(foreign)

    flagcheck = read(d / "flagcheck.txt")
    m = re.search(r"^FLAG-SUMMARY .*$", flagcheck, re.M)
    if m:
        meta["flagcheck"] = m[0]
    m = re.search(r"^FLAG-FULL .*$", flagcheck, re.M)
    if m:
        meta["flagcheck_full"] = m[0]

    envstr = read(d / "envstr.txt")
    m = re.search(r"^ENVSTR .*$", envstr, re.M)
    if m:
        meta["envnames"] = m[0]

    body = "".join(f"{k}={v}\n" for k, v in meta.items())
    (d / "meta.txt").write_text(body, encoding="utf-8")
    print(body, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
