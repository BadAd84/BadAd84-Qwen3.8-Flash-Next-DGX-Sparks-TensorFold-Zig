#!/usr/bin/env bash
# zab_rm.sh <label> <base arm> <ours arm>   on spark6 (box copy ~/work/bench/), detached:
#   setsid nohup bash ~/work/bench/zab_rm.sh LABEL "BASE" "OURS" </dev/null >/dev/null 2>&1 &
# The recipe's TTFT + RigMark A/B (AGENTS.md: RigMark is part of every benchmark; TTFT is a first-class metric).
# An arm is one string of start.sh settings, e.g. "PREPARE=0 IMAGE=tensorfold-qwen38:zmerge5 TF_FLASHNEXT_...=1",
# plus an optional PATCHES=<the image's OTS patch set, no spaces> that is not passed to start.sh but recorded as
# RigMark's ots_patches (our images carry no tf.ots-patches label) and an optional ENGINE=python (not passed either):
# the arm runs the recipe's last Python release (0.6.0, clone PY_RECIPE, default ~/qwen-py) instead of its Zig
# release (~/qwen-zig); "-" skips the arm. Every arm runs in its own hold of ~/work/gpu.lock (one hold an arm,
# ~35-90 min), in ORDER (default "base ours"):
#   1. boot: Zig: ~/work/zarm.sh <run> 0 <settings> (a restart through the recipe's start.sh, the golden replies, no
#      decode passes; its log ~/work/zab-<run>.log is copied here as BOOT lines). Python: the Zig serve stopped
#      (~/qwen-zig/stop.sh), then `PY_RECIPE/start.sh restart` with the settings (kernel cache PY_KERNEL_CACHE,
#      default ~/.cache/tensorfold-qwen38-py, kept apart from the Zig recipe's), then ~/work/qf_harness.py golden, all
#      into ~/work/zab-<run>.log. Then the serve must answer /health and run the arm's image;
#   2. golden: ~/work/zgold_cmp.py against the arm's reference: Zig, GOLDEN_REF (default ~/work/zab3/zgold-base-c1.json,
#      the stock image's replies); Python, PY_GOLDEN_REF (default ~/work/zab3/zgold-python-stock.json): the Python
#      engine's replies are not the Zig engine's (another checkpoint and kernels), so a Python arm is checked against
#      the Python stock serve's own replies, recorded on its first boot (a Python stock arm with no reference file
#      writes it from this boot, says so on a GOLD line, then compares: 6/6 by construction on that boot). Every arm
#      logs "GOLD <arm> reference <file> (<kind>)". An arm that is not 6/6 identical has no speed result, so its
#      steps 2b-5 are skipped;
#   2b. Python arms (PY_DECODE=1, default): the decode probes the Zig arms get from zarm.sh / the merge verify runs,
#      in this hold: ~/work/qf_run.py's decode matrix (prose and code at 1 / 2 / 4 clients, 512 tokens, greedy,
#      thinking off, one pass; DECODE lines, rows ~/work/zab-<run>.jsonl) and ~/work/merge/v/pmz.py's six one-client
#      prose requests (PM lines, rows ~/work/zab-<run>-pm.jsonl);
#   3. shape: the raw SSE of one short streamed reply, thinking off and on (SHAPE lines; ttft.py reads this shape);
#   4. ttft.py (TTFT=1, default; beside this script): cold ~1k / 8k / 32k / 120k thinking off and on, a warm +2k turn
#      on a kept ~100k conversation, idle and with 3 other streams decoding, TTFT_REPS reps (default 3; TTFT_ARGS adds
#      options);
#   5. RigMark (RIGMARK=1, default): effort_check.py (the live server honours the extra body: EFFORT lines), then
#      rigmark_run.sh: the standard suite, comparison ID RIGMARK_ID (default zrm-<label>: one per sweep, so both arms
#      get byte-identical prompts), extra body {"reasoning_effort": "low"} (RigMark's published card for this model
#      family), metadata: Zig, rigmark/metadata-zig-stock.json for an arm on STOCK_IMAGE (default
#      tensorfold-qwen38:zig-db28187) with no settings beyond PREPARE / IMAGE and no PATCHES, else
#      metadata-zig-ours.json; Python, rigmark/metadata-python-stock.json for an arm on PY_STOCK_IMAGE (default
#      tensorfold-qwen38:v0.6.1, the recipe 0.6.0's published image) on the same terms, else metadata-python-ours.json.
#      A Python arm runs RigMark with --skip-prefill (RIGMARK lines say so): the Python server has no /tokenize and
#      takes only text prompts on /v1/completions (TensorFold v0.6.1 cuda/http.py, cuda/server.py App._prepare),
#      so RigMark's token-id prefill pairs cannot run on it; ttft.py's cold prompts are its prefill measure.
#      Receipts and cards: ~/work/bench/rigmark/runs/.
# Cold prefill: the Zig server ignores cache_salt, but RigMark's prefill prompts (completion token ids) keep no state
# in its prompt cache (rigmark_run.sh), so they are cold on any run; every arm still gets a fresh boot.
# Log ~/work/bench/zabrm-<label>.log; summary: python3 ~/work/bench/zab_rm_sum.py ~/work/bench/zabrm-<label>.log
# (golden, TTFT and RigMark sections, ours against base; exit 1 on a golden DIFF, a boot failure, a TTFT or RigMark
# error). A Zig arm's serve is left running (the next lock holder boots its own); a Python arm stops its serve
# (PY_RECIPE/stop.sh, still inside its hold) and leaves the Zig serve stopped. Overrides (the offline dry run,
# tests/test_rigmark_dryrun.sh, uses them): WORK, PORT, LOCK, ZABRM_DIR (the log's directory), RIGMARK_OUT,
# ZIG_RECIPE (default ~/qwen-zig), PY_RECIPE, PY_KERNEL_CACHE.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/work} PORT=${PORT:-8888} LOCK=${LOCK:-$HOME/work/gpu.lock}
STOCK_IMAGE=${STOCK_IMAGE:-tensorfold-qwen38:zig-db28187}
GOLDEN_REF=${GOLDEN_REF:-$WORK/zab3/zgold-base-c1.json}
ZIG_RECIPE=${ZIG_RECIPE:-$HOME/qwen-zig}
PY_RECIPE=${PY_RECIPE:-$HOME/qwen-py} PY_STOCK_IMAGE=${PY_STOCK_IMAGE:-tensorfold-qwen38:v0.6.1}
PY_GOLDEN_REF=${PY_GOLDEN_REF:-$WORK/zab3/zgold-python-stock.json}
PY_KERNEL_CACHE=${PY_KERNEL_CACHE:-$HOME/.cache/tensorfold-qwen38-py}
TTFT_REPS=${TTFT_REPS:-3} TTFT_ARGS=${TTFT_ARGS:-} RIGMARK=${RIGMARK:-1} TTFT=${TTFT:-1} PY_DECODE=${PY_DECODE:-1}
EXTRA='{"reasoning_effort": "low"}'
now() { date +%T; }

py_boot() {   # run settings...   (inside the lock) the Python recipe's restart and its golden replies -> zab-<run>.log
  local run=$1; shift
  {
    echo "=== $run start $(date -Is) engine python ($PY_RECIPE @ $(git -C "$PY_RECIPE" describe --tags --always 2>/dev/null)) env: $*"
    ( cd "$ZIG_RECIPE" && ./stop.sh </dev/null ) 2>&1 | tail -1
    ( cd "$PY_RECIPE" && env KERNEL_CACHE="$PY_KERNEL_CACHE" "$@" ./start.sh restart </dev/null ) 2>&1 \
      | grep -a "answered\|LIVE\|rror\|die\|WARN"
    docker inspect qwen38-flash-next-tf --format '{{.Config.Image}} {{json .Args}}' 2>&1
    ( cd "$WORK" && python3 qf_harness.py golden "zgold-$run.json" ) 2>&1 | tail -1
    echo "=== ZARM $run DONE $(date -Is)"
  } > "$WORK/zab-$run.log" 2>&1
}

py_decode() {   # arm run   (inside the lock, after golden) the decode probes a Zig arm gets from zarm.sh / mverify
  # runs: qf_run.py's decode matrix (prose and code at 1 / 2 / 4 clients, 512 tokens, greedy, thinking off, one pass)
  # with /metrics' drafted / accepted around it, summarised by ~/work/zig_sum.py from the client's side as the Zig
  # rows are ((completion tokens - 1) / (elapsed - ttft); qf_run.py's own "tok/s med" lines divide by the engine's
  # decode_s, which the Zig server does not send), then merge/v/pmz.py's six one-client prose requests (PM_N=6,
  # MODE py: the stream's own stats block) when the box has it
  local A=$1 run=$2 d0 a0
  metric() { curl -s -m 5 "http://127.0.0.1:$PORT/metrics" | awk -v k="tensorfold:$1" '$1==k {print $2}'; }
  d0=$(metric mtp_drafted_total); a0=$(metric mtp_accepted_total)
  { ( cd "$WORK" && RUNS=1 python3 qf_run.py "$run-p1" "zab-$run.jsonl" decode ) 2>&1; echo "exit $?"; } \
    | sed "s/^/DECODE $A /"
  echo "DECODE $A pass 1 /metrics: drafted ${d0:-?} -> $(metric mtp_drafted_total) accepted ${a0:-?} -> $(metric mtp_accepted_total) (rows zab-$run.jsonl)"
  python3 "$WORK/zig_sum.py" "$WORK/zab-$run.jsonl" 2>&1 | sed "s/^/DECODE $A client /"
  if [ -f "$WORK/merge/v/pmz.py" ]; then
    { ( cd "$WORK/merge/v" && PM_N=6 python3 pmz.py "$run" "$WORK/zab-$run-pm.jsonl" py ) 2>&1; echo "exit $?"; } \
      | sed "s/^/PM $A /"
  else
    echo "PM $A skipped: no $WORK/merge/v/pmz.py"
  fi
}

arm() {   # label arm spec   (inside the lock)
  local L=$1 A=$2 SPEC=$3 RUN="zrm-$1-$2" patches="" image="" engine=zig tpl kv running ref kind stock_image
  local -a settings=()
  for kv in $SPEC; do
    case "$kv" in
      PATCHES=*) patches=${kv#PATCHES=} ;;
      ENGINE=*) engine=${kv#ENGINE=} ;;
      IMAGE=*) image=${kv#IMAGE=}; settings+=("$kv") ;;
      *) settings+=("$kv") ;;
    esac
  done
  ARM_ENGINE=$engine
  case "$engine" in
    zig) stock_image=$STOCK_IMAGE ref=$GOLDEN_REF kind="the Zig stock image's replies" ;;
    python) stock_image=$PY_STOCK_IMAGE ref=$PY_GOLDEN_REF
            kind="python self-reference: the Python stock serve's replies from its first boot, not zgold-base-c1" ;;
    *) echo "== $(now) ARM $A: unknown ENGINE=$engine (zig or python)"; return 1 ;;
  esac
  image=${image:-$stock_image}
  tpl="$HERE/rigmark/metadata-$engine-ours.json"
  if [ "$image" = "$stock_image" ] && [ -z "$patches" ] && \
     [ -z "$(printf '%s\n' "${settings[@]}" | grep -Ev '^(PREPARE|IMAGE)=')" ]; then
    tpl="$HERE/rigmark/metadata-$engine-stock.json"
  fi
  echo "== $(now) ARM $A lock held: engine $engine ${settings[*]}${patches:+ PATCHES=$patches} (metadata $(basename "$tpl"))"
  if [ "$engine" = python ]; then
    py_boot "$RUN" "${settings[@]}"
  else
    "$WORK/zarm.sh" "$RUN" 0 "${settings[@]}"
  fi
  sed "s/^/BOOT $A /" "$WORK/zab-$RUN.log"
  running=$(docker inspect qwen38-flash-next-tf --format '{{.Config.Image}}' 2>/dev/null)
  if ! curl -sf -m 5 -o /dev/null "http://127.0.0.1:$PORT/health"; then
    echo "BOOT $A FAILED: /health does not answer"; return 1
  fi
  if [ "$running" != "$image" ]; then
    echo "BOOT $A FAILED: the serve runs $running, not $image"; return 1
  fi
  if [ "$engine" = python ] && [ ! -f "$ref" ] && [ "$(basename "$tpl")" = metadata-python-stock.json ] \
     && [ -s "$WORK/zgold-$RUN.json" ]; then
    mkdir -p "$(dirname "$ref")" && cp "$WORK/zgold-$RUN.json" "$ref" \
      && echo "GOLD $A reference created from this boot: $ref (no reference file yet; this is the Python stock serve's first recorded boot)"
  fi
  [ -f "$ref" ] || echo "GOLD $A no reference file: $ref (a Python arm's reference comes from the Python stock arm's first boot)"
  echo "GOLD $A reference $ref ($kind)"
  python3 "$WORK/zgold_cmp.py" "$ref" "$WORK/zgold-$RUN.json" > "$WORK/zgold-$RUN.cmp" 2>&1
  local gold=$?
  { cat "$WORK/zgold-$RUN.cmp"; echo "exit $gold"; } | sed "s/^/GOLD $A /"
  if [ "$gold" != 0 ]; then
    echo "== $(now) ARM $A golden not identical: no speed result (TTFT and RigMark skipped)"; return 1
  fi
  if [ "$engine" = python ] && [ "$PY_DECODE" = 1 ]; then
    py_decode "$A" "$RUN"
  fi
  for th in false true; do
    curl -sN -m 120 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Say hello.\"}], \"max_tokens\": 6, \"temperature\": 0, \"stream\": true, \"chat_template_kwargs\": {\"enable_thinking\": $th}}" \
      | head -c 6000 | sed "s/^/SHAPE $A thinking=$th /"
  done
  if [ "$TTFT" = 1 ]; then
    # shellcheck disable=SC2086  # TTFT_ARGS is a list of options
    { python3 "$HERE/ttft.py" "$PORT" --reps "$TTFT_REPS" $TTFT_ARGS 2>&1; echo "exit $?"; } | sed "s/^/TTFT $A /"
  fi
  if [ "$RIGMARK" = 1 ]; then
    local rm_args=${RIGMARK_ARGS:-}
    if [ "$engine" = python ]; then
      rm_args="$rm_args --skip-prefill"
      echo "RIGMARK $A note: --skip-prefill (the Python server has no /tokenize and no token-id completion prompts)"
    fi
    { python3 "$HERE/effort_check.py" "$PORT" "$EXTRA" 2>&1; echo "exit $?"; } | sed "s/^/EFFORT $A /"
    RIGMARK_ARGS="$rm_args" RIGMARK_OTS_PATCHES="$patches" bash "$HERE/rigmark_run.sh" "$RUN" "$RIGMARK_ID" "$tpl" \
      "$EXTRA" 2>&1 | sed "s/^/RIGMARK $A /"
  fi
  echo "== $(now) ARM $A done"
}

if [ "${1:-}" = --arm ]; then
  shift
  RIGMARK_ID=${RIGMARK_ID:?}
  ARM_ENGINE=zig
  arm "$@"
  rc=$?
  if [ "$ARM_ENGINE" = python ]; then      # a Python arm leaves no serve behind (the next holder boots its own)
    ( cd "$PY_RECIPE" && ./stop.sh </dev/null ) 2>&1 | sed "s/^/STOP $2 /"
  fi
  exit $rc
fi
L=${1:?label} BASE=${2:?base arm settings or -} OURS=${3:?ours arm settings or -}
export RIGMARK_ID=${RIGMARK_ID:-zrm-$L}
ORDER=${ORDER:-base ours}
LOG="${ZABRM_DIR:-$HERE}/zabrm-$L.log"
exec >> "$LOG" 2>&1
echo "== $(now) ZABRM $L START: comparison $RIGMARK_ID order $ORDER base=$BASE ours=$OURS"
for a in $ORDER; do
  case "$a" in base) spec=$BASE ;; ours) spec=$OURS ;; *) echo "== $(now) unknown arm $a in ORDER"; continue ;; esac
  [ "$spec" = - ] && continue
  echo "== $(now) ARM $a waiting for $LOCK"
  # -o: the lock is flock's alone, so a process an arm leaves running (a daemon a boot starts) never holds it after
  flock -o "$LOCK" bash "$HERE/zab_rm.sh" --arm "$L" "$a" "$spec"
done
echo "== $(now) ZABRM $L DONE"
