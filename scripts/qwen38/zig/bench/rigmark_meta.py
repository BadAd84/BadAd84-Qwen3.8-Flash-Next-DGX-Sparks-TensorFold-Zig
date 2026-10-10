#!/usr/bin/env python3
"""rigmark_meta.py <metadata template> <out.json> [port]   on spark6: RigMark's appliance metadata for the recipe's
server on <port> (default 8888), either engine: TensorFold's Zig server (`tensorfold-native serve`, the recipe's
release 1.0.0) or its Python package's server (`tensorfold serve`, the recipe's last Python release 0.6.0). The
template's fixed fields (rigmark/metadata-{zig,python}-*.json beside this script) plus the fields read live from the
serving container and the box. Exit 1, with the reason, when the container cannot be found or a fixed field
contradicts the live serve (the template is then wrong, never silently "fixed").

Live fields: serving_image (tag + image id), recipe_patches / ots_patches (the image's tf.patches / tf.ots-patches
labels; for an image without the latter, $RIGMARK_OTS_PATCHES, which zab_rm.sh sets from an arm's PATCHES=),
model_revision (Zig: the checkpoint snapshot in the container's arguments; Python: the Hub id's refs/main in the
Hugging Face cache the container mounts, the snapshot its offline server resolves), drafter (Zig: the checkpoint's
MTP head, off with --no-drafts, else its depth / confidence / FP8 settings from the env; Python: --mtp-drafts /
--mtp-confidence, the chain rule and prompt-lookup copies from the env), kv_cache_dtype (--kv-dtype), scheduler
(--parallel, --max-tokens, prefill rows / tail or the SSD n-gram reader, default thinking and sampling flags),
context_limit (checked against --context), accelerator (nvidia-smi), competing_traffic (the server's /health at
start: the Zig server's live.connections, the Python server's requests_running), kernel and os, tf_env (every
TF_FLASHNEXT_* and TENSORFOLD_* the run sets: the container's env less the image's own ENV lines, e.g.
TENSORFOLD_VISION_PYTHONPATH; a path value as its last component; TENSORFOLD_API_KEY and TENSORFOLD_CUDA_KERNELS
left out).
Checks (exit 1): one serve on the port; the template's model and context_limit are the container's; exactly one GPU
and it is a GB10 (the template's hardware); the template's "expect" block: expect.engine is the container's engine
(zig / python, from the command before `serve`); expect.kv_dtype, when set, is its --kv-dtype; expect.image, when set,
is its image (by image id); expect.env / expect.args, when set, are exactly its TF_FLASHNEXT_* / TENSORFOLD_* settings
(as tf_env) / its serve arguments after the model less --host and --port; a template whose arm is "stock: ..." needs
the stock image (expect.stock_image, by image id), exactly the recipe's start.sh env (expect.recipe_env), the
recipe's serve arguments when the template names them (expect.recipe_args) and no OTS patches; an "ours: ..."
template refuses that same stock configuration. The "expect" block is not written to the output. Nothing secret is
read: no credentials, no endpoint URL (RigMark never writes the URL either)."""
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
    """The running container whose ``tensorfold-native serve`` / ``tensorfold serve`` listens on ``port``."""

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
        raise SystemExit(f"rigmark_meta: {len(found)} tensorfold serve containers listen on port {port}; need one")
    return found[0]


def engine_of(args: list[str]) -> str:
    """The serve's engine from the command before ``serve``: "zig" (``tensorfold-native``, the recipe's 1.0.0
    image), "python" (``tensorfold``, the Python package's CLI: the recipe's 0.x images), else "unknown"."""

    names = {Path(a).name for a in args[:args.index("serve")]} if "serve" in args else set()
    return "zig" if "tensorfold-native" in names else "python" if "tensorfold" in names else "unknown"


def serve_args(args: list[str]) -> list[str]:
    """The serve arguments after the model, less --host / --port and their values (the bind, not the setting)."""

    rest, out, i = args[args.index("serve") + 2:], [], 0
    while i < len(rest):
        if rest[i] in ("--host", "--port"):
            i += 2
            continue
        out.append(rest[i])
        i += 1
    return out


def snapshot_rev(path: str) -> str:
    """``.../models--org--name/snapshots/<rev>`` -> "org/name @ rev"."""

    parts = Path(path).parts
    repo = next((p for p in parts if p.startswith("models--")), "")
    rev = parts[parts.index("snapshots") + 1] if "snapshots" in parts else "unknown"
    return f"{repo[len('models--'):].replace('--', '/')} @ {rev}"


def model_of(c: dict, args: list[str]) -> tuple[str, str]:
    """(model, revision) the container serves: the Zig server names a snapshot directory; the Python server names a
    Hub id and resolves it offline (HF_HUB_OFFLINE=1) through refs/main in the cache it mounts at
    /root/.cache/huggingface (its HF_HOME)."""

    spec = args[args.index("serve") + 1]
    if spec.startswith("/"):
        name, rev = snapshot_rev(spec).split(" @ ")
        return name, rev
    cache = next((m.get("Source") for m in c.get("Mounts") or []
                  if m.get("Destination") == "/root/.cache/huggingface"), None)
    ref = Path(cache or "/nonexistent") / "hub" / f"models--{spec.replace('/', '--')}" / "refs" / "main"
    if not ref.is_file():
        raise SystemExit(f"rigmark_meta: {spec}: no refs/main in the container's Hugging Face cache ({cache})")
    return spec, ref.read_text().strip()


def gpus() -> list[str]:
    out = subprocess.check_output(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"],
                                  text=True)
    return [ln.strip() for ln in out.splitlines() if ln.strip()]


def running(port: int) -> str:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=5) as r:
            health = json.load(r)
    except Exception as exc:  # noqa: BLE001  (recorded, not fatal: RigMark then fails on the endpoint itself)
        return f"unknown (/health unreadable: {type(exc).__name__})"
    quiet = "the harness holds spark6's GPU lock and runs nothing else meanwhile"
    if "live" not in health and "requests_running" in health:          # the Python server's /health (cuda/health.py)
        n = health["requests_running"]
        return (f"none checked at start (/health requests_running 0; {quiet})" if n == 0 else
                f"NOT QUIET at start: /health requests_running {n} (streams {health.get('streams')})")
    live = health.get("live") or {}
    n, waiting = live.get("connections"), live.get("waiting")
    if n is None:
        return "unknown (/health has no live.connections)"
    return (f"none checked at start (/health live.connections 0; {quiet})" if n == 0 else
            f"NOT QUIET at start: /health live.connections {n} ({waiting} waiting)")


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
    engine = engine_of(args)
    if engine != expect.get("engine"):
        raise SystemExit(f"rigmark_meta: the template is for the {expect.get('engine')} engine, the container runs "
                         f"{engine} ({' '.join(args[:args.index('serve') + 1])})")
    name, rev = model_of(c, args)
    if name != meta["model"]:
        raise SystemExit(f"rigmark_meta: the template names {meta['model']}, the container serves {name}")
    context = int(opt.get("--context", "0"))
    if context != meta["context_limit"]:
        raise SystemExit(f"rigmark_meta: the template says context_limit {meta['context_limit']}, the container "
                         f"runs --context {context}")
    if "kv_dtype" in expect and opt.get("--kv-dtype") != expect["kv_dtype"]:
        raise SystemExit(f"rigmark_meta: the template's KV cache is {expect['kv_dtype']}, the container runs "
                         f"--kv-dtype {opt.get('--kv-dtype')}")
    cards = gpus()
    if len(cards) != 1 or "GB10" not in cards[0]:
        raise SystemExit(f"rigmark_meta: the template's hardware is one GB10, nvidia-smi lists {cards}")
    image = c["Config"].get("Image", "")
    image_id = c.get("Image", "")
    sargs = serve_args(args)
    if "image" in expect and image_id != docker_json("image", "inspect", expect["image"])[0]["Id"]:
        raise SystemExit(f"rigmark_meta: the template's image is {expect['image']}, the container runs {image} "
                         f"({image_id[:19]})")
    if "env" in expect and tf != expect["env"]:
        raise SystemExit(f"rigmark_meta: the template's env differs from the container's: "
                         f"{sorted(set(tf.items()) ^ set(expect['env'].items()))}")
    if "args" in expect and sargs != expect["args"]:
        raise SystemExit(f"rigmark_meta: the template's serve arguments are {' '.join(expect['args'])}, the "
                         f"container runs {' '.join(sargs)}")
    ots = labels.get("tf.ots-patches") or os.environ.get("RIGMARK_OTS_PATCHES", "").strip()
    arm = str(meta.get("arm", ""))
    stock_tag = expect.get("stock_image")
    if stock_tag is None or "recipe_env" not in expect:
        raise SystemExit("rigmark_meta: the template has no expect.stock_image / expect.recipe_env")
    stock_id = docker_json("image", "inspect", stock_tag)[0]["Id"]
    recipe_args = expect.get("recipe_args")
    is_stock = (image_id == stock_id and tf == expect["recipe_env"] and not ots
                and (recipe_args is None or sargs == recipe_args))
    if arm.startswith("stock:") and not is_stock:
        why = []
        if image_id != stock_id:
            why.append(f"image {image} ({image_id[:19]}) is not {stock_tag} ({stock_id[:19]})")
        if tf != expect["recipe_env"]:
            extra = sorted(set(tf.items()) ^ set(expect["recipe_env"].items()))
            why.append(f"env differs from the recipe's: {extra}")
        if recipe_args is not None and sargs != recipe_args:
            why.append(f"serve arguments differ from the recipe's: {' '.join(sargs)}")
        if ots:
            why.append(f"OTS patches named: {ots}")
        raise SystemExit("rigmark_meta: a stock template on a serve that is not stock: " + "; ".join(why))
    if arm.startswith("ours:") and is_stock:
        raise SystemExit(f"rigmark_meta: an ours template on the stock serve ({stock_tag}, the recipe's env, no "
                         f"OTS patches)")
    if not (arm.startswith("stock:") or arm.startswith("ours:")):
        raise SystemExit(f"rigmark_meta: the template's arm must start 'stock:' or 'ours:', not {arm[:40]!r}")
    if engine == "python":
        rule = tf.get("TENSORFOLD_CHAIN_RULE")
        chain = (f"chain rule TENSORFOLD_CHAIN_RULE {rule}" + (f" at TENSORFOLD_CHAIN_T {tf['TENSORFOLD_CHAIN_T']}"
                                                               if tf.get("TENSORFOLD_CHAIN_T") else "")
                 if rule else "v0.6.1's chain rule (a draft under --mtp-confidence ends the chain)")
        drafter = (f"the checkpoint's MTP head, up to --mtp-drafts {opt.get('--mtp-drafts', 'the engine default')} "
                   f"drafts a round, --mtp-confidence {opt.get('--mtp-confidence', 'the engine default')}, {chain}, "
                   f"prompt-lookup copies TENSORFOLD_MTP_COPY {tf.get('TENSORFOLD_MTP_COPY') or 'unset'}; drafts are "
                   f"verified (the recipe: replies match serial decoding)")
        scheduler = (f"--parallel {opt.get('--parallel', '?')} streams, --max-tokens {opt.get('--max-tokens', '?')}, "
                     f"prompt piece rows TENSORFOLD_PREFILL_ROWS {tf.get('TENSORFOLD_PREFILL_ROWS') or 'default'}, "
                     f"n-gram tables {'read from SSD (--ple-on-ssd)' if '--ple-on-ssd' in args else 'in memory'}, "
                     f"thinking {'on' if '--thinking' in args else 'off'} by default, server sampling defaults "
                     f"--temperature {opt.get('--temperature', '?')} --top-p {opt.get('--top-p', '?')} --top-k "
                     f"{opt.get('--top-k', '?')} (RigMark's requests set their own)")
    else:
        if "--no-drafts" in args:
            drafter = "none (--no-drafts)"
        else:
            depth = tf.get("TF_FLASHNEXT_DEPTH") or "the engine default"
            confidence = tf.get("TF_FLASHNEXT_CONFIDENCE") or "the engine default"
            weights = "FP8 (TF_FLASHNEXT_MTP_FP8 overlay)" if tf.get("TF_FLASHNEXT_MTP_FP8") else "as the checkpoint"
            int4 = ", INT4 draft head (TF_FLASHNEXT_DRAFT_INT4=1)" if tf.get("TF_FLASHNEXT_DRAFT_INT4") == "1" else ""
            drafter = (f"the checkpoint's integrated MTP head, up to TF_FLASHNEXT_DEPTH {depth} drafts a round, "
                       f"confidence {confidence}, MTP weights {weights}{int4}; drafts are verified (the recipe: "
                       f"replies match serial decoding)")
        scheduler = (f"--parallel {opt.get('--parallel', '?')} streams, --max-tokens {opt.get('--max-tokens', '?')}, "
                     f"prefill rows {tf.get('TF_FLASHNEXT_PREFILL_ROWS') or 'default'}, prefill tail "
                     f"{tf.get('TF_FLASHNEXT_PREFILL_TAIL') or 'default'}, thinking "
                     f"{'on' if '--thinking' in args else 'off'} by default, server sampling defaults --temperature "
                     f"{opt.get('--temperature', '?')} --top-p {opt.get('--top-p', '?')} --top-k "
                     f"{opt.get('--top-k', '?')} (RigMark's requests set their own)")
    live = {
        "serving_image": f"{image} (image id {image_id})",
        "recipe_patches": labels.get("tf.patches", "none (no tf.patches label)"),
        "ots_patches": ots or "none (no tf.ots-patches label, RIGMARK_OTS_PATCHES unset)",
        "model_revision": rev,
        "drafter": drafter,
        "kv_cache_dtype": f"{opt.get('--kv-dtype') or 'the engine default'} (--kv-dtype)",
        "scheduler": scheduler,
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
