#!/usr/bin/env python3
"""rigmark_meta.py <metadata template> <out.json> [port]   on spark6: RigMark's appliance metadata for the recipe's
Zig server on <port> (default 8888): the template's fixed fields (rigmark/metadata-zig-*.json beside this script) plus
the fields read live from the serving container and the box. Exit 1, with the reason, when the container cannot be
found or a fixed field contradicts the live serve (the template is then wrong, never silently "fixed").

Live fields: serving_image (tag + image id), recipe_patches / ots_patches (the image's tf.patches / tf.ots-patches
labels; for an image without the latter, $RIGMARK_OTS_PATCHES, which zab_rm.sh sets from an arm's PATCHES=),
model_revision (the checkpoint snapshot in the container's arguments), drafter (the checkpoint's MTP head: off with
--no-drafts, else its depth / confidence / FP8 settings from the env), kv_cache_dtype (--kv-dtype), scheduler
(--parallel, --max-tokens, prefill rows / tail, default thinking and sampling flags), context_limit (checked against
--context), accelerator (nvidia-smi), competing_traffic (the server's /health live.connections at start), kernel and
os, tf_env (every TF_FLASHNEXT_* and TENSORFOLD_* the run sets: the container's env less the image's own ENV lines,
e.g. TENSORFOLD_VISION_PYTHONPATH; a path value as its last component; TENSORFOLD_API_KEY and TENSORFOLD_CUDA_KERNELS
left out).
Checks (exit 1): one tensorfold-native serve on the port; the template's model and context_limit are the container's;
exactly one GPU and it is a GB10 (the template's hardware); the template's "expect" block: a template whose arm is
"stock: ..." needs the stock image (expect.stock_image, by image id), exactly the recipe's start.sh env
(expect.recipe_env) and no OTS patches; an "ours: ..." template refuses that same stock configuration. The "expect"
block is not written to the output. Nothing secret is read: no credentials, no endpoint URL (RigMark never writes the
URL either)."""
import json
import os
import platform
import subprocess
import sys
import urllib.request
from pathlib import Path

LIVE = "FILLED PER RUN"
SKIP_ENV = ("TENSORFOLD_API_KEY", "TENSORFOLD_CUDA_KERNELS")


def docker_json(*args: str):
    return json.loads(subprocess.check_output(["docker", *args], text=True))


def serving_container(port: int) -> dict:
    """The running container whose ``tensorfold-native serve`` listens on ``port``."""

    ids = subprocess.check_output(["docker", "ps", "-q"], text=True).split()
    found = []
    for c in docker_json("inspect", *ids) if ids else []:
        args = list(c.get("Args") or [])
        if "serve" not in args:
            continue
        opt = dict(zip(args, args[1:]))
        if opt.get("--port", "8888") == str(port):
            found.append(c)
    if len(found) != 1:
        raise SystemExit(f"rigmark_meta: {len(found)} tensorfold-native serve containers listen on port {port}; "
                         f"need one")
    return found[0]


def snapshot_rev(path: str) -> str:
    """``.../models--org--name/snapshots/<rev>`` -> "org/name @ rev"."""

    parts = Path(path).parts
    repo = next((p for p in parts if p.startswith("models--")), "")
    rev = parts[parts.index("snapshots") + 1] if "snapshots" in parts else "unknown"
    return f"{repo[len('models--'):].replace('--', '/')} @ {rev}"


def gpus() -> list[str]:
    out = subprocess.check_output(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"],
                                  text=True)
    return [ln.strip() for ln in out.splitlines() if ln.strip()]


def running(port: int) -> str:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=5) as r:
            live = json.load(r).get("live") or {}
    except Exception as exc:  # noqa: BLE001  (recorded, not fatal: RigMark then fails on the endpoint itself)
        return f"unknown (/health unreadable: {type(exc).__name__})"
    n, waiting = live.get("connections"), live.get("waiting")
    if n is None:
        return "unknown (/health has no live.connections)"
    return ("none checked at start (/health live.connections 0; the harness holds spark6's GPU lock and runs nothing "
            "else meanwhile)" if n == 0 else f"NOT QUIET at start: /health live.connections {n} ({waiting} waiting)")


def shown(value: str) -> str:
    """An env value as recorded: a container path as its last component (no directories in public metadata)."""

    return f"(path) {Path(value).name}" if value.startswith("/") else value


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    meta = json.loads(Path(sys.argv[1]).read_text())
    expect = meta.pop("expect", {})
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 8888
    c = serving_container(port)
    args = list(c.get("Args") or [])
    opt = dict(zip(args, args[1:]))
    env = dict(e.split("=", 1) for e in c["Config"].get("Env") or [] if "=" in e)
    baked = dict(e.split("=", 1) for e in docker_json("image", "inspect", c.get("Image", ""))[0]["Config"].get("Env")
                 or [] if "=" in e)
    labels = c["Config"].get("Labels") or {}
    tf = {k: v for k, v in sorted(env.items())       # the settings the run added, not the image's own ENV lines
          if (k.startswith("TF_FLASHNEXT_") or k.startswith("TENSORFOLD_")) and k not in SKIP_ENV
          and baked.get(k) != v}
    model = snapshot_rev(args[args.index("serve") + 1])
    name, rev = model.split(" @ ")
    if name != meta["model"]:
        raise SystemExit(f"rigmark_meta: the template names {meta['model']}, the container serves {name}")
    context = int(opt.get("--context", "0"))
    if context != meta["context_limit"]:
        raise SystemExit(f"rigmark_meta: the template says context_limit {meta['context_limit']}, the container "
                         f"runs --context {context}")
    cards = gpus()
    if len(cards) != 1 or "GB10" not in cards[0]:
        raise SystemExit(f"rigmark_meta: the template's hardware is one GB10, nvidia-smi lists {cards}")
    image = c["Config"].get("Image", "")
    image_id = c.get("Image", "")
    ots = labels.get("tf.ots-patches") or os.environ.get("RIGMARK_OTS_PATCHES", "").strip()
    arm = str(meta.get("arm", ""))
    stock_tag = expect.get("stock_image")
    if stock_tag is None or "recipe_env" not in expect:
        raise SystemExit("rigmark_meta: the template has no expect.stock_image / expect.recipe_env")
    stock_id = docker_json("image", "inspect", stock_tag)[0]["Id"]
    is_stock = image_id == stock_id and tf == expect["recipe_env"] and not ots
    if arm.startswith("stock:") and not is_stock:
        why = []
        if image_id != stock_id:
            why.append(f"image {image} ({image_id[:19]}) is not {stock_tag} ({stock_id[:19]})")
        if tf != expect["recipe_env"]:
            extra = sorted(set(tf.items()) ^ set(expect["recipe_env"].items()))
            why.append(f"env differs from the recipe's: {extra}")
        if ots:
            why.append(f"OTS patches named: {ots}")
        raise SystemExit("rigmark_meta: a stock template on a serve that is not stock: " + "; ".join(why))
    if arm.startswith("ours:") and is_stock:
        raise SystemExit(f"rigmark_meta: an ours template on the stock serve ({stock_tag}, the recipe's env, no "
                         f"OTS patches)")
    if not (arm.startswith("stock:") or arm.startswith("ours:")):
        raise SystemExit(f"rigmark_meta: the template's arm must start 'stock:' or 'ours:', not {arm[:40]!r}")
    if "--no-drafts" in args:
        drafter = "none (--no-drafts)"
    else:
        depth = tf.get("TF_FLASHNEXT_DEPTH") or "the engine default"
        confidence = tf.get("TF_FLASHNEXT_CONFIDENCE") or "the engine default"
        weights = "FP8 (TF_FLASHNEXT_MTP_FP8 overlay)" if tf.get("TF_FLASHNEXT_MTP_FP8") else "as the checkpoint"
        int4 = ", INT4 draft head (TF_FLASHNEXT_DRAFT_INT4=1)" if tf.get("TF_FLASHNEXT_DRAFT_INT4") == "1" else ""
        drafter = (f"the checkpoint's integrated MTP head, up to TF_FLASHNEXT_DEPTH {depth} drafts a round, "
                   f"confidence {confidence}, MTP weights {weights}{int4}; drafts are verified (the recipe: replies "
                   f"match serial decoding)")
    live = {
        "serving_image": f"{image} (image id {image_id})",
        "recipe_patches": labels.get("tf.patches", "none (no tf.patches label)"),
        "ots_patches": ots or "none (no tf.ots-patches label, RIGMARK_OTS_PATCHES unset)",
        "model_revision": rev,
        "drafter": drafter,
        "kv_cache_dtype": f"{opt.get('--kv-dtype') or 'the engine default'} (--kv-dtype)",
        "scheduler": (f"--parallel {opt.get('--parallel', '?')} streams, --max-tokens {opt.get('--max-tokens', '?')}, "
                      f"prefill rows {tf.get('TF_FLASHNEXT_PREFILL_ROWS') or 'default'}, prefill tail "
                      f"{tf.get('TF_FLASHNEXT_PREFILL_TAIL') or 'default'}, thinking "
                      f"{'on' if '--thinking' in args else 'off'} by default, server sampling defaults --temperature "
                      f"{opt.get('--temperature', '?')} --top-p {opt.get('--top-p', '?')} --top-k "
                      f"{opt.get('--top-k', '?')} (RigMark's requests set their own)"),
        "accelerator": f"{cards[0]} (nvidia-smi: name, driver)",
        "competing_traffic": running(port),
        "kernel": platform.release(),
        "os": next((ln.split("=", 1)[1].strip('"') for ln in Path("/etc/os-release").read_text().splitlines()
                    if ln.startswith("PRETTY_NAME=")), "unknown"),
        "tf_env": {k: shown(v) for k, v in tf.items()},
    }
    for k, v in live.items():
        meta[k] = v
    left = [k for k, v in meta.items() if v == LIVE]
    if left:
        raise SystemExit(f"rigmark_meta: fields still {LIVE!r}: {', '.join(left)}")
    Path(sys.argv[2]).write_text(json.dumps(meta, indent=2) + "\n")
    print(f"rigmark_meta: {sys.argv[2]}: {image}, {name} @ {rev[:12]}, {'stock' if is_stock else 'ours'}, "
          f"kv {opt.get('--kv-dtype')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
