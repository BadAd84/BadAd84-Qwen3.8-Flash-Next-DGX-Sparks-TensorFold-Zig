#!/bin/bash
# rigmark_run.sh <label> <comparison-id> <metadata template> [extra-body JSON]   on spark6 (box copy ~/work/bench/):
# RigMark (github.com/alexellis/rigmark, ~/rigmark at the commit pinned in spark6's ~/INVENTORY.md) against the
# recipe's Zig server on $PORT (default 8888), the standard suite: code / prose / structured x5 (8,192-token cap,
# reasoning included), cold + immediate-replay prefill at 8K / 32K / 64K x3, C1 / C2 / C4 x3 (256-token cap).
#   <metadata template>: rigmark/metadata-zig-<stock|ours>.json beside this script; rigmark_meta.py (beside it too)
#     fills the live fields from the serving container (image, tf.patches / tf.ots-patches labels, model revision,
#     drafter, KV dtype, scheduler, TF_FLASHNEXT_* / TENSORFOLD_* env, the GPU, /health) and refuses a template the
#     live serve contradicts. RIGMARK_OTS_PATCHES (set by zab_rm.sh from an arm's PATCHES=) names the OTS patch set
#     of an image that carries no tf.ots-patches label.
#   [extra-body]: default {"reasoning_effort": "low"}, byte-for-byte the request body of RigMark's published card for
#     this model family (results/reference/qwen38-flash-next-nvidia-nvfp4-tp2-low: vLLM, two Sparks, NVFP4). The Zig
#     server reads a top-level reasoning_effort (src/server/fields.zig thinkingFields): "low" is a level the Qwen3.8
#     chat template names, and an effort other than "none" turns thinking on, so every request is thinking on at
#     effort low (checked on the live server: /tokenize renders the template's "Reasoning effort is set to low"
#     instruction for this body, and the reply's tensorfold block says enable_thinking true, reasoning_effort low).
#     The same value in every arm of a sweep; another value is another comparison (RigMark's rule) and gets its own
#     ID. Strict `rigmark compare` against that card still reports mismatches it cannot match from here (its protocol
#     1.1.0, RigMark revision e748928, 4,096-token decode cap, its comparison ID): compare with --allow-mismatch.
#   <comparison-id>: one per sweep (every arm of it), so the arms get byte-identical prompts.
# Writes $RIGMARK_OUT (default ~/work/bench/rigmark/runs)/<label>-<UTC stamp>.json (the receipt), .card.txt (the share
# card) and .metadata.json; prints RigMark's progress, then "receipt <path>", "card <path>", "summary {json}"
# (rigmark_sum.py line: the headline numbers, so harness summaries need only the log) and "exit N" (N = RigMark's exit;
# a refusal, e.g. a cold prefill sample the server reports cached, is non-zero and keeps its receipt with an "error").
# Cold-prefill isolation: RigMark sends a fresh cache_salt per pair; the Zig server does not read cache_salt (unknown
# fields are ignored), but its prompt cache (src/core/prompt_cache.zig) keeps states only at a chat prompt's history
# (src/server/prompt.zig history_len; prompts of 4,096+ tokens), and RigMark's prefill pairs are /v1/completions
# token-id prompts with no history: they keep nothing. So the cold samples are cold on any run, and the "immediate
# replay" is cold too (spark6, 2026-10-10: replay cached 0 at 8K / 32K / 64K, replay TTFT = cold TTFT). zab_rm.sh still
# boots every arm fresh. Time: ~9 min a run measured on zmerge5 (up to ~50 min if every decode sample reasons to the
# 8,192-token cap). RIGMARK_ARGS adds suite flags (e.g. --skip-concurrency).
set -u
LABEL=${1:?label} CID=${2:?comparison-id} TEMPLATE=${3:?metadata template}
EXTRA=${4:-'{"reasoning_effort": "low"}'}
PORT=${PORT:-8888} RM=${RIGMARK_DIR:-$HOME/rigmark} OUT=${RIGMARK_OUT:-$HOME/work/bench/rigmark/runs}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT" || { echo "exit 1"; exit 1; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BASE="$OUT/$LABEL-$STAMP"
if ! python3 "$HERE/rigmark_meta.py" "$TEMPLATE" "$BASE.metadata.json" "$PORT"; then
  echo "metadata failed"; echo "exit 1"; exit 1
fi
echo "rigmark $(git -C "$RM" rev-parse HEAD 2>/dev/null) $(git -C "$RM" status --porcelain | wc -l) changed files; comparison $CID; extra body $EXTRA"
# shellcheck disable=SC2086  # RIGMARK_ARGS is a list of flags
python3 "$RM/rigmark" run --base-url "http://127.0.0.1:$PORT" --model auto --label "$LABEL" --comparison-id "$CID" \
  --metadata "$BASE.metadata.json" --extra-body "$EXTRA" --output "$BASE.json" ${RIGMARK_ARGS:-} 2>&1
rc=$?
if [ -f "$BASE.json" ]; then
  echo "receipt $BASE.json"
  [ -f "$BASE.card.txt" ] || python3 "$RM/rigmark" report --save "$BASE.json" > /dev/null 2>&1
  [ -f "$BASE.card.txt" ] && echo "card $BASE.card.txt"
  python3 "$HERE/rigmark_sum.py" line "$BASE.json" || { [ "$rc" = 0 ] && rc=1; }
else
  echo "no receipt written"
fi
echo "exit $rc"
exit $rc
