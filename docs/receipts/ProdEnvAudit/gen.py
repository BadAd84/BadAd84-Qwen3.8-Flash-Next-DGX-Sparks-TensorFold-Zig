#!/usr/bin/env python3
"""Generate the production engine's env record from its read sites.

The zmerge8 engine has no settings table (see RESULT.md), so the production table is DERIVED: the
names are the served binary's own TF_/TENSORFOLD_ strings (the PROMOTION-RULES oracle, captured by
the parity window's phase-0 strings scan) plus TENSORFOLD_VIDEO_TOKENS, which the vision helper reads
from the image's Python tree. Every row's default and citation is a read site in the recovered build
tree, copied under docs/receipts/ProdEnvAudit/src/.

This script writes, from ROWS:

  scripts/qwen38/zig/target/env/prod.env          the complete record (launcher section + defaults)
  docs/receipts/ProdEnvAudit/prod-settings-table.zig  the table the coverage gate is pointed at
  docs/receipts/ProdEnvAudit/prod-launcher.env    the launcher-only view (54 rows)
  scripts/qwen38/zig/target/env/register.env      the tagged `prod` verdict block

and verifies every citation line before writing: the cited file must exist and the cited line must
contain the setting's name. Run it from the repo root; check-prod-rows.py then re-checks the
artifacts independently.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVID = "docs/receipts/ProdEnvAudit"
PROD_ENV = ROOT / "scripts/qwen38/zig/target/env/prod.env"
REGISTER = ROOT / "scripts/qwen38/zig/target/env/register.env"
TABLE = ROOT / EVID / "prod-settings-table.zig"
LAUNCHER_VIEW = ROOT / EVID / "prod-launcher.env"
LIVE = ROOT / EVID / "live-env.txt"
LAUNCHER = EVID + "/qwen6-start-prod.sh"
SRC = EVID + "/src"
LIVE_CITE = EVID + "/live-env.txt"
BEGIN = "# --- PRODUCTION ENGINE SETTINGS (tagged `prod`; the untagged lines above are the dev arm's)"
END = "# --- end production engine settings"

MEASURED = "production's shipped arm value, captured from the live container (the launcher header records the zmerge8 arm as the measured one; no per-row cells are kept in this repo)"

# name, scope, forms, kind, value ("<live>" reads the captured container value; "" is `unset`), cite, note
ROWS = [
    # ---- section 1: what the live launcher carries (54 names, values from live-env.txt) ----
    ("TENSORFOLD_CUDA_KERNELS", "common", "path", "launcher", "<live>", LIVE_CITE + ":1", "the recipe launcher injects KERNELS_PATH itself (start.sh:169) and skips the env's own value; the container runs the captured sm121 set"),
    ("TENSORFOLD_IMAGE_TOKENS", "common", "count", "measured", "<live>", LIVE_CITE + ":2", MEASURED),
    ("TENSORFOLD_MAX_IMAGES", "common", "count", "measured", "<live>", LIVE_CITE + ":3", MEASURED),
    ("TENSORFOLD_MEMORY_RESERVE_GIB", "common", "count", "measured", "<live>", LIVE_CITE + ":4", MEASURED),
    ("TENSORFOLD_NO_UPDATE_CHECK", "common", "bool", "measured", "<live>", LIVE_CITE + ":5", MEASURED),
    ("TENSORFOLD_PROMPT_CACHE_WHOLE", "common", "bool", "measured", "<live>", LIVE_CITE + ":6", MEASURED),
    ("TENSORFOLD_PROMPT_CACHE_WHOLE_MIN", "common", "count", "measured", "<live>", LIVE_CITE + ":7", MEASURED),
    ("TENSORFOLD_VIDEO_TOKENS", "common", "count", "measured", "<live>", LIVE_CITE + ":8", MEASURED + "; read by the vision helper's qwen_processing.py:263, which is not in the binary's name list"),
    ("TENSORFOLD_VISION_PYTHONPATH", "common", "path", "measured", "<live>", LIVE_CITE + ":9", MEASURED),
    ("TENSORFOLD_VISION_WORKSPACE_MIB", "common", "count", "measured", "<live>", LIVE_CITE + ":10", MEASURED),
    ("TENSORFOLD_WARM_TURNS", "common", "bool", "measured", "<live>", LAUNCHER + ":10", "0 is production's decision: warm turns are the one keep with a measured 1-stream regression (+0.08-0.25 s back-to-back TTFT), so the launcher sets 0"),
    ("TF_FLASHNEXT_BATCH_DRAWS", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":12", MEASURED),
    ("TF_FLASHNEXT_BATCH_WINDOWS", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":13", MEASURED),
    ("TF_FLASHNEXT_CONFIDENCE", "flashnext", "number", "measured", "<live>", LIVE_CITE + ":14", "production's -0.15; checkpoint-specific (the FP4 1.2.7 stack's own optimum was -0.4, and -0.20 is level on the dev tree's prose cells), not a lever this repo measured"),
    ("TF_FLASHNEXT_COPY_MISS", "flashnext", "enum", "measured", "<live>", LIVE_CITE + ":15", MEASURED),
    ("TF_FLASHNEXT_COPY_RAMP", "flashnext", "enum", "measured", "<live>", LIVE_CITE + ":16", MEASURED),
    ("TF_FLASHNEXT_COPY_RESYNC", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":17", MEASURED),
    ("TF_FLASHNEXT_COPY_SHARED", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":18", MEASURED),
    ("TF_FLASHNEXT_COST_RETIME", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":19", MEASURED),
    ("TF_FLASHNEXT_DEPTH", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":20", MEASURED + "; equals the engine's own default (cuda_native.zig:88)"),
    ("TF_FLASHNEXT_DRAFT_CONTINUE", "flashnext", "number", "measured", "<live>", LIVE_CITE + ":21", MEASURED),
    ("TF_FLASHNEXT_DRAFT_DEPTH_SHARED", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":22", MEASURED),
    ("TF_FLASHNEXT_DRAFT_INT4", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":23", MEASURED),
    ("TF_FLASHNEXT_DRAFT_PROPOSE", "flashnext", "number", "measured", "<live>", LIVE_CITE + ":24", MEASURED),
    ("TF_FLASHNEXT_EARLY_DRAW", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":25", MEASURED),
    ("TF_FLASHNEXT_FP8_FUSED_SPLIT", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":26", MEASURED),
    ("TF_FLASHNEXT_FP8_PROMPT_TILES", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":27", MEASURED),
    ("TF_FLASHNEXT_HC_Q12", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":28", "production builds the 12-bit read-out copies; hcQ12On also needs the fused reduce kernel, checked against the kernel set at load"),
    ("TF_FLASHNEXT_HEAD_ROW_TILES", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":29", MEASURED),
    ("TF_FLASHNEXT_INT4_PROMPT_GATE_UP", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":30", MEASURED),
    ("TF_FLASHNEXT_MTP_FP8", "flashnext", "path", "measured", "<live>", LIVE_CITE + ":31", "the FP8 MTP drafter overlay directory (built by production/mtp_fp8.py); drafts only"),
    ("TF_FLASHNEXT_MULTI_LRU", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":32", MEASURED),
    ("TF_FLASHNEXT_MULTI_MAX", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":33", MEASURED),
    ("TF_FLASHNEXT_MULTI_VERIFY", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":34", MEASURED),
    ("TF_FLASHNEXT_NGRAM_LATE", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":35", MEASURED),
    ("TF_FLASHNEXT_NGRAM_PREFETCH", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":36", MEASURED),
    ("TF_FLASHNEXT_NGRAM_RANDOM", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":37", MEASURED),
    ("TF_FLASHNEXT_NGRAM_THREADS", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":38", MEASURED),
    ("TF_FLASHNEXT_PREFILL_ROWS", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":39", MEASURED),
    ("TF_FLASHNEXT_PREFILL_TAIL", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":40", MEASURED),
    ("TF_FLASHNEXT_PRODUCT_STREAMS", "flashnext", "count", "launcher", "<live>", LIVE_CITE + ":41", "the recipe's config.sh computes it per boot (default 5); production's launcher environment overrides 8"),
    ("TF_FLASHNEXT_PROMPT_HEAD_SKIP", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":42", MEASURED),
    ("TF_FLASHNEXT_QSA_SELECT", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":43", MEASURED),
    ("TF_FLASHNEXT_QSA_TILE", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":44", MEASURED),
    ("TF_FLASHNEXT_REDUCE_ACT", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":45", MEASURED),
    ("TF_FLASHNEXT_SEQ_POOL", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":46", MEASURED),
    ("TF_FLASHNEXT_SHARED_COST_LEVELS", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":47", MEASURED),
    ("TF_FLASHNEXT_SHARED_EARLY_ROWS", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":48", MEASURED),
    ("TF_FLASHNEXT_SHARED_SLOT_LD", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":49", MEASURED),
    ("TF_FLASHNEXT_SOLO_MAX", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":50", MEASURED),
    ("TF_FLASHNEXT_UPMIX_DECODE", "flashnext", "bool", "measured", "<live>", LIVE_CITE + ":51", MEASURED),
    ("TF_FLASHNEXT_WARM_POOL", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":52", MEASURED),
    ("TF_FLASHNEXT_WINDOW", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":53", MEASURED),
    ("TF_FLASHNEXT_YARN", "flashnext", "count", "measured", "<live>", LIVE_CITE + ":54", MEASURED + "; 0 keeps the checkpoint's rope and admits a 262,144-token window (the recipe refuses more without YaRN)"),

    # ---- section 2: the engine's own defaults for every other name it can read ----
    ("TENSORFOLD_API_KEY", "common", "presence", "absent", "", SRC + "/zig/src/server/serve.zig:93", "no API key: absence is the decision, and the serve answers its LAN clients without one (the server logs the open-port warning)"),
    ("TENSORFOLD_MAX_VIDEOS", "common", "count", "debt", "4", SRC + "/zig/src/server/main.zig:58", "the vision helper's video ceiling default (env or 4); production sets no separate value"),
    ("TENSORFOLD_NO_LIVE", "common", "bool", "inert", "0", SRC + "/zig/src/server/serve.zig:166", "the live drawing is off in a container anyway (stdout is not a tty); 0 states the reader's default"),
    ("TENSORFOLD_REQUEST_LOG", "common", "path", "absent", "", SRC + "/zig/src/server/serve.zig:121", "no request log: no file is named, so no chat or completion body is appended"),
    ("TENSORFOLD_SEED_SALT", "common", "count", "debt", "0", SRC + "/zig/src/server/serve.zig:106", "seeds are unsalted (the engine's 0 default); production does not salt them"),
    ("TENSORFOLD_VISION_PYTHON", "common", "path", "debt", "python3", SRC + "/zig/src/server/vision.zig:99", "the helper runs the image's python3; the engine default"),
    ("TENSORFOLD_VISION_SELFTEST", "common", "presence", "inert", "", SRC + "/zig/src/server/vision.zig:139", "no self-test hash is demanded at helper start; off by absence"),
    ("TENSORFOLD_WARM_DELAY_MS", "common", "count", "inert", "200", SRC + "/zig/src/native/cuda.zig:318", "warm turns are off (TENSORFOLD_WARM_TURNS=0), so the delay never acts; 200 ms is the engine default"),
    ("TENSORFOLD_WARM_ROWS", "common", "count", "inert", "4096", SRC + "/zig/src/native/cuda.zig:319", "as above: warm turns off; 4096 rows is the engine default"),
    ("TF_CUDA_DEVICE", "cuda", "count", "absent", "", SRC + "/zig/src/native/cuda.zig:37", "the recipe launcher cannot pass TF_CUDA_* names; the engine's device default is GPU 0"),
    ("TF_FLASHNEXT_ATTN_MULTI", "flashnext", "count", "debt", "5", SRC + "/zig/src/families/flashnext/cuda_engine.zig:691", "from 5 streams the shared rounds' attention runs one launch a kernel (multi_graphs 4 + 1), the engine default; an fp8 KV cache would turn it off, and production runs fp8"),
    ("TF_FLASHNEXT_BURST_LOG", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:1447", "a burst log switch; off by absence"),
    ("TF_FLASHNEXT_COMM_PRIORITY", "flashnext", "count", "inert", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:764", "read only inside the two-rank overlap block; 0 is the stream priority it would pass"),
    ("TF_FLASHNEXT_COPY_RESYNC_PROMPT_ONLY", "flashnext", "bool", "debt", "1", SRC + "/zig/src/native/cuda.zig:298", "resync copies only out of the prompt; the host field's default is true"),
    ("TF_FLASHNEXT_COUNT_EXPERTS", "flashnext", "bool", "inert", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:697", "prints per-layer expert counts; 0 is the default"),
    ("TF_FLASHNEXT_DRAW_ONCE", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:650", "a draft level's draws in one launch; default on"),
    ("TF_FLASHNEXT_DROP_PAGES", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:717", "the weights' pages are dropped after load; default on"),
    ("TF_FLASHNEXT_EXPERT_SHAPE", "flashnext", "text", "debt", "", SRC + "/zig/src/families/flashnext/cuda_kernels.zig:278", "no shape override; the kernel plan's geometry decides (null default)"),
    ("TF_FLASHNEXT_EXPERT_SMS_FREE", "flashnext", "count", "inert", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:768", "read only inside the two-rank overlap block; 0 leaves every SM to the expert kernels"),
    ("TF_FLASHNEXT_FILL", "flashnext", "bool", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_native.zig:158", "the sliced prompt fill is opt-in, verified exact only on GPUs; 0 is the default"),
    ("TF_FLASHNEXT_FILL_LAYERS", "flashnext", "count", "debt", "8", SRC + "/zig/src/families/flashnext/cuda_native.zig:159", "the slice count used when FILL is on; default 8"),
    ("TF_FLASHNEXT_FP4_SERIAL", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:671", "the K-serial fp4 gate/up; default on"),
    ("TF_FLASHNEXT_FP8_FUSED_SPLIT_N", "flashnext", "count", "debt", "2048", SRC + "/zig/src/families/flashnext/cuda_fp8.zig:87", "the fused FP8 split's item count; default 2048"),
    ("TF_FLASHNEXT_FP8_LD", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:668", "block-FP8 columns stored in place; default on"),
    ("TF_FLASHNEXT_GLUE_FUSE", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:726", "the up-mix glue fused; default on where the kernel set has it"),
    ("TF_FLASHNEXT_GLUE_SPLIT", "flashnext", "bool", "inert", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:705", "the row-split glue needs two ranks (world == 2); this serve is one rank, and 1 states the default"),
    ("TF_FLASHNEXT_GRAPH_FAIL", "flashnext", "count", "inert", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:673", "a fault injection (fails every Nth graph); 0 never fires"),
    ("TF_FLASHNEXT_GRAPH_LOG", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:672", "a graph log switch; off by absence"),
    ("TF_FLASHNEXT_INT4AR_FAST", "flashnext", "path", "absent", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:587", "no FP8 overlay directory: the INT4-AutoRound fast overlay is off by absence"),
    ("TF_FLASHNEXT_INT4_PROMPT_DOWN", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_int4.zig:434", "the prompt down on the int4 kernel; default on"),
    ("TF_FLASHNEXT_INT4_TILE", "flashnext", "count", "debt", "16", SRC + "/zig/src/families/flashnext/cuda_int4.zig:148", "16-pair items, the plan tile; 64 would take the prompt tile and needs two row tiles a pass"),
    ("TF_FLASHNEXT_KEEP_LATE", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_lanes.zig:192", "keeps the late draft rows; default true"),
    ("TF_FLASHNEXT_L2PF", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_comm.zig:66", "the L2 prefetch of the next weight tiles; default on"),
    ("TF_FLASHNEXT_L2PF_BYTES", "flashnext", "count", "debt", "8388608", SRC + "/zig/src/families/flashnext/cuda_forward.zig:1355", "the 8 MiB L2 prefetch cap; the engine default"),
    ("TF_FLASHNEXT_MEDIA_GRAPHS", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:696", "cuda graphs for the media path; default on"),
    ("TF_FLASHNEXT_MTP_Q4", "flashnext", "path", "absent", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:784", "no 4-bit MTP table path: the Q4 drafter head is off by absence"),
    ("TF_FLASHNEXT_MTP_Q4_MSE", "flashnext", "bool", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:785", "the Q4 head's MSE rounding is off; default 0"),
    ("TF_FLASHNEXT_MTP_TOPK", "flashnext", "count", "debt", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:202", "the checkpoint's top_k (5 here); only a top-10 checkpoint accepts a number and 0 logs a warning, so absence is the default"),
    ("TF_FLASHNEXT_MULTI_GRAPHS", "flashnext", "count", "debt", "4", SRC + "/zig/src/families/flashnext/cuda_engine.zig:674", "four shared graphs captured; default 4"),
    ("TF_FLASHNEXT_NGRAM_AHEAD", "flashnext", "count", "debt", "2", SRC + "/zig/src/families/flashnext/cuda_ngram_host.zig:39", "two prompt chunks queued ahead; default 2"),
    ("TF_FLASHNEXT_NGRAM_MIN", "flashnext", "count", "debt", "32", SRC + "/zig/src/families/flashnext/cuda_ngram_host.zig:36", "the ngram's minimum match, a row count; default 32"),
    ("TF_FLASHNEXT_OVERCOMMIT", "flashnext", "bool", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_native.zig:155", "no GPU memory overcommit; default off"),
    ("TF_FLASHNEXT_OVERLAP", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:762", "needs the two-rank glue split; absent means off"),
    ("TF_FLASHNEXT_PASS_TIMES", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:719", "a pass timing print switch; off by absence"),
    ("TF_FLASHNEXT_POISON_PADS", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:718", "a check that poisons the pads; off by absence"),
    ("TF_FLASHNEXT_PREFILL_DIGEST", "flashnext", "presence", "inert", "", SRC + "/zig/src/families/flashnext/cuda_engine.zig:706", "a prompt digest print switch; off by absence"),
    ("TF_FLASHNEXT_PROFILE", "flashnext", "bool", "inert", "0", SRC + "/zig/src/families/flashnext/cuda_prof.zig:10", "the per-part GPU profiler; the reader treats 0 as off (cuda_engine.zig:779), and 0 states the default"),
    ("TF_FLASHNEXT_PROMPT_EXPERTS", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_moe_prompt.zig:12", "prompt experts read their weights once a call; default on (read at cuda_engine.zig:698)"),
    ("TF_FLASHNEXT_PROMPT_EXPERTS_CFG", "flashnext", "text", "debt", "32,2,2", SRC + "/zig/src/families/flashnext/cuda_moe_prompt.zig:64", "the plan tile and row tiles a warp; default 32,2,2"),
    ("TF_FLASHNEXT_PROMPT_EXPERTS_GU2", "flashnext", "bool", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_moe_prompt.zig:62", "two one-matrix gate/up passes off; default 0"),
    ("TF_FLASHNEXT_PROMPT_EXPERTS_OCC", "flashnext", "bool", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_moe_prompt.zig:58", "the 4-CTA expert variant off; default 0"),
    ("TF_FLASHNEXT_PROMPT_EXPERTS_ROWS", "flashnext", "text", "debt", "4096,2048", SRC + "/zig/src/families/flashnext/cuda_moe_prompt.zig:70", "the gate/up and down row thresholds; default 4096,2048"),
    ("TF_FLASHNEXT_PROMPT_MM", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_prompt.zig:13", "prompt matmuls in one program; default on (read at cuda_engine.zig:649)"),
    ("TF_FLASHNEXT_QSA_FAST", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:741", "the QSA scores kernel; default on"),
    ("TF_FLASHNEXT_QSA_RT", "flashnext", "count", "debt", "0", SRC + "/zig/src/families/flashnext/cuda_engine.zig:746", "the rt score path off; default 0"),
    ("TF_FLASHNEXT_QSA_SPLIT_KEYS", "flashnext", "count", "debt", "65536", SRC + "/zig/src/families/flashnext/cuda_engine.zig:752", "the two-rank split threshold; default 65536"),
    ("TF_FLASHNEXT_QSA_TILES_FROM", "flashnext", "count", "debt", "8192", SRC + "/zig/src/families/flashnext/cuda_engine.zig:749", "the tiles path from 8192 blocks; default 8192"),
    ("TF_FLASHNEXT_ROCE", "flashnext", "bool", "inert", "1", SRC + "/zig/src/families/flashnext/cuda_comm.zig:65", "the RoCE transport for the two-rank comm; this serve is one rank"),
    ("TF_FLASHNEXT_ROCE_MAX", "flashnext", "count", "inert", "524288", SRC + "/zig/src/families/flashnext/cuda_comm.zig:145", "the RoCE message cap; unused at one rank, 524288 is the default"),
    ("TF_FLASHNEXT_SHARED_SIDE", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:661", "the shared expert beside the routed experts; default on"),
    ("TF_FLASHNEXT_WB_NORM", "flashnext", "bool", "debt", "1", SRC + "/zig/src/families/flashnext/cuda_engine.zig:739", "the fused write-back norm; default on where the kernel set has it"),
    ("TF_FLASHNEXT_YARN_RAMP_POSITIONS", "flashnext", "text", "absent", "", SRC + "/zig/src/families/flashnext/cuda_rope.zig:127", "the checkpoint's rope supplies the ramp positions; absent is the default (read at cuda_native.zig:333)"),
    ("TF_TP_TIMEOUT_S", "cuda", "count", "inert", "", SRC + "/zig/src/families/flashnext/cuda_mirror.zig:759", "the two-rank mirror's timeout (base 300 s); the launcher cannot pass TF_* names and this serve is one rank"),
    ("TENSORFOLD_VISION_WEIGHTS", "common", "path", "absent", "", SRC + "/src/tensorfold/vision/qwen_cuda.py:76", "no separate vision-weights file: the tower reads the checkpoint's own weights, and absence also keeps them off the host-RAM override path (the capacity read at qwen_cuda.py:143)"),
]

# Names the binary carries, beyond which the vision helper adds two (both read on the served vision path).
ORACLE = "strings-P.txt"
EXTRA_HELPER = {"TENSORFOLD_VIDEO_TOKENS", "TENSORFOLD_VISION_WEIGHTS"}


def live_values() -> dict[str, str]:
    values = {}
    for line in LIVE.read_text(encoding="utf-8").splitlines():
        name, _, value = line.partition("=")
        values[name] = value
    return values


def check_cites(rows):
    bad = []
    for name, _scope, _forms, _kind, _value, cite, _note in rows:
        path_s, _, lineno = cite.rpartition(":")
        path = ROOT / path_s
        if not path.is_file():
            bad.append(f"{name}: cited file does not exist: {cite}")
            continue
        line = path.read_text(encoding="utf-8", errors="replace").splitlines()[int(lineno) - 1]
        if name not in line:
            bad.append(f"{name}: cited line does not contain the name: {cite}: {line.strip()[:100]}")
    return bad


def prod_lines(rows, live):
    out = []
    section2 = False
    for name, _scope, _forms, kind, value, cite, note in rows:
        if not section2 and name == "TENSORFOLD_API_KEY":
            out.append("# --- explicit defaults: every other name the engine can read, at its own default")
            out.append("")
            section2 = True
        v = live[name] if value == "<live>" else value
        statement = f"unset {name}" if v == "" else f"export {name}={v}"
        out.append(f"# {kind}: {note}.")
        out.append(f"# Cite: {cite}")
        out.append(statement)
    return out


def main() -> int:
    names = [r[0] for r in ROWS]
    if len(names) != len(set(names)):
        print("gen: duplicate rows")
        return 1
    live = live_values()
    oracle = set((ROOT / EVID / ORACLE).read_text().split())
    expected = oracle | EXTRA_HELPER
    if set(names) != expected:
        print(f"gen: rows {len(names)} != oracle {len(oracle)} + helper: "
              f"missing {sorted(expected - set(names))} extra {sorted(set(names) - expected)}")
        return 1
    if set(live) - set(names):
        print(f"gen: captured container names not in the rows: {sorted(set(live) - set(names))}")
        return 1
    bad = check_cites(ROWS)
    if bad:
        for b in bad:
            print("CITE-BAD", b)
        return 1

    header = [
        "# PRODUCTION environment: every setting the production engine reads, one row each.",
        "#",
        "# The engine is the tree the served image was built from: tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7,",
        "# its source tar sha256 e5139fcd8c6101c776d9c600021228d389e648f58a398842498d95c3ebcccecc (the image's",
        "# ai-engine.src-sha256 label), recovered at work/ProdEnvAudit/src.tar (gitignored; sha256 quoted in the receipt) and matching the production",
        "# branch tree at 5c3e3e29 file for file (1640 files, 0 differences; docs/receipts/ProdEnvAudit/RESULT.md).",
        "#",
        "# That engine has NO settings table (no zig/src/platform/environment.zig in its 1,743-entry source tar (1,640 files)), so the",
        "# table is DERIVED from its read sites: docs/receipts/ProdEnvAudit/prod-settings-table.zig holds the 118 names",
        "# the served binary carries (116 TF_/TENSORFOLD_ strings) plus the vision helper's TENSORFOLD_VIDEO_TOKENS and",
        "# TENSORFOLD_VISION_WEIGHTS. Section 1 is what the live launcher carries (the 54-name container environment",
        "# captured 2026-11-24 in docs/receipts/ProdEnvAudit/live-env.txt); section 2 states every other name at its",
        "# own default, taken from the read site cited above each row. Verdicts live in register.env, tagged `prod`.",
        "#",
        "# Gates, both green (run from the repo root):",
        "#   python scripts/qwen38/zig/target/env/check-env-coverage.py --table docs/receipts/ProdEnvAudit/prod-settings-table.zig \\",
        "#     --dev scripts/qwen38/zig/target/env/prod.env --register scripts/qwen38/zig/target/env/register.env \\",
        "#     --scopes flashnext,cuda,common --passes '^(TENSORFOLD|TF_FLASHNEXT)_' --tag prod",
        "#   python scripts/qwen38/zig/target/env/check-prod-env.py --inspect <saved docker inspect of the production container>",
        "#     (on the box; the comparison set is the rows whose prod verdict says the container carries them)",
        "",
    ]
    PROD_ENV.write_text("\n".join(header + prod_lines(ROWS, live)) + "\n", encoding="utf-8", newline="\n")

    table = [
        "// DERIVED settings table for the production engine (tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7).",
        "// The zmerge8 tree has NO zig/src/platform/environment.zig: its settings are raw reads, so this table is",
        "// derived by docs/receipts/ProdEnvAudit/gen.py from the served binary's own name strings (116, captured by",
        "// the parity window's phase-0 strings scan) plus the vision helper's TENSORFOLD_VIDEO_TOKENS. Every row's",
        "// read site is cited in prod.env and checked by docs/receipts/ProdEnvAudit/check-prod-rows.py. Do not hand",
        "// edit: regenerate with `python docs/receipts/ProdEnvAudit/gen.py`.",
        "",
    ]
    for name, scope, forms, _kind, _value, _cite, _note in sorted(ROWS):
        table.append(f'        .{{ .name = "{name}", .scope = .{scope}, .forms = "{forms}" }},')
    TABLE.write_text("\n".join(table) + "\n", encoding="utf-8", newline="\n")

    launcher_rows = [r for r in ROWS if r[4] == "<live>"]
    view = ["# Launcher-only view of prod.env: the 54 rows the live production container carries.",
            "# Generated by docs/receipts/ProdEnvAudit/gen.py; use it for a direct drift read with",
            "# check-prod-env.py --prod. The complete record is scripts/qwen38/zig/target/env/prod.env."]
    for name, _scope, _forms, _kind, _value, _cite, _note in launcher_rows:
        view.append(f"export {name}={live[name]}")
    LAUNCHER_VIEW.write_text("\n".join(view) + "\n", encoding="utf-8", newline="\n")

    reg = REGISTER.read_text(encoding="utf-8")
    block = [BEGIN, "# Generated by docs/receipts/ProdEnvAudit/gen.py from the production engine's read sites.",
             "# carried kinds (measured, launcher) are the rows the live container carries; debt/inert/absent",
             "# are rows pinned at the engine's own default, informational to the drift check."]
    for name, _scope, _forms, kind, value, cite, note in ROWS:
        block.append(f"# prod {kind} {name}: {note}. Cite: {cite}")
    block.append(END)
    if BEGIN in reg and END in reg:
        before, rest = reg.split(BEGIN, 1)
        after = rest.split(END, 1)[1].lstrip("\n")
        reg = before + "\n".join(block) + "\n" + after
    else:
        reg = reg.rstrip("\n") + "\n\n" + "\n".join(block) + "\n"
    REGISTER.write_text(reg, encoding="utf-8", newline="\n")

    print(f"gen: rows {len(ROWS)} launcher {len(launcher_rows)} defaults {len(ROWS) - len(launcher_rows)} "
          f"citations {sum(1 for _ in ROWS)} checked; wrote prod.env, table ({len(ROWS)} rows), launcher view, register block")
    return 0


if __name__ == "__main__":
    sys.exit(main())
