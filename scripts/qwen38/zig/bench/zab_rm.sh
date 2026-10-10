#!/usr/bin/env bash
# zab_rm.sh <label> <base arm> <ours arm>   on spark6 (box copy ~/work/bench/), detached:
#   setsid nohup bash ~/work/bench/zab_rm.sh LABEL "BASE" "OURS" </dev/null >/dev/null 2>&1 &
# The Zig serve's TTFT + RigMark A/B (AGENTS.md: RigMark is part of every benchmark; TTFT is a first-class metric).
# An arm is one string of start.sh settings, e.g. "PREPARE=0 IMAGE=tensorfold-qwen38:zmerge5 TF_FLASHNEXT_...=1",
# plus an optional PATCHES=<the image's OTS patch set, no spaces> that is not passed to start.sh but recorded as
# RigMark's ots_patches (our images carry no tf.ots-patches label); "-" skips the arm. Every arm runs in its own hold
# of ~/work/gpu.lock (one hold an arm, ~35-55 min), in ORDER (default "base ours"):
#   1. boot: ~/work/zarm.sh <run> 0 <settings> (a restart through the recipe's start.sh, the golden replies, no
#      decode passes; its log ~/work/zab-<run>.log is copied here as BOOT lines), then the serve must answer /health
#      and run the arm's image;
#   2. golden: ~/work/zgold_cmp.py against GOLDEN_REF (default ~/work/zab3/zgold-base-c1.json, the stock image's
#      replies): an arm that is not 6/6 identical has no speed result, so its steps 3-5 are skipped;
#   3. shape: the raw SSE of one short streamed reply, thinking off and on (SHAPE lines; ttft.py reads this shape);
#   4. ttft.py (beside this script): cold ~1k / 8k / 32k / 120k thinking off and on, a warm +2k turn on a kept ~100k
#      conversation, idle and with 3 other streams decoding, TTFT_REPS reps (default 3; TTFT_ARGS adds options);
#   5. RigMark (RIGMARK=1, default): effort_check.py (the live server honours the extra body: EFFORT lines), then
#      rigmark_run.sh: the standard suite, comparison ID RIGMARK_ID (default zrm-<label>: one per sweep, so both arms
#      get byte-identical prompts), extra body {"reasoning_effort": "low"} (RigMark's published card for this model
#      family), metadata rigmark/metadata-zig-stock.json for an arm on STOCK_IMAGE (default
#      tensorfold-qwen38:zig-db28187) with no settings beyond PREPARE / IMAGE and no PATCHES, else
#      metadata-zig-ours.json. Receipts and cards: ~/work/bench/rigmark/runs/.
# Cold prefill: the Zig server ignores cache_salt, but RigMark's prefill prompts (completion token ids) keep no state
# in its prompt cache (rigmark_run.sh), so they are cold on any run; every arm still gets a fresh boot.
# Log ~/work/bench/zabrm-<label>.log; summary: python3 ~/work/bench/zab_rm_sum.py ~/work/bench/zabrm-<label>.log
# (golden, TTFT and RigMark sections, ours against base; exit 1 on a golden DIFF, a boot failure, a TTFT or RigMark
# error). The last arm's serve is left running; the next lock holder boots its own. Overrides (the offline dry run,
# tests/test_rigmark_dryrun.sh, uses them): WORK, PORT, LOCK, ZABRM_DIR (the log's directory), RIGMARK_OUT.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/work} PORT=${PORT:-8888} LOCK=${LOCK:-$HOME/work/gpu.lock}
STOCK_IMAGE=${STOCK_IMAGE:-tensorfold-qwen38:zig-db28187}
GOLDEN_REF=${GOLDEN_REF:-$WORK/zab3/zgold-base-c1.json}
TTFT_REPS=${TTFT_REPS:-3} TTFT_ARGS=${TTFT_ARGS:-} RIGMARK=${RIGMARK:-1}
EXTRA='{"reasoning_effort": "low"}'
now() { date +%T; }

arm() {   # label arm spec   (inside the lock)
  local L=$1 A=$2 SPEC=$3 RUN="zrm-$1-$2" patches="" image="" tpl kv running
  local -a settings=()
  for kv in $SPEC; do
    case "$kv" in
      PATCHES=*) patches=${kv#PATCHES=} ;;
      IMAGE=*) image=${kv#IMAGE=}; settings+=("$kv") ;;
      *) settings+=("$kv") ;;
    esac
  done
  image=${image:-$STOCK_IMAGE}
  tpl="$HERE/rigmark/metadata-zig-ours.json"
  if [ "$image" = "$STOCK_IMAGE" ] && [ -z "$patches" ] && \
     [ -z "$(printf '%s\n' "${settings[@]}" | grep -Ev '^(PREPARE|IMAGE)=')" ]; then
    tpl="$HERE/rigmark/metadata-zig-stock.json"
  fi
  echo "== $(now) ARM $A lock held: ${settings[*]}${patches:+ PATCHES=$patches} (metadata $(basename "$tpl"))"
  "$WORK/zarm.sh" "$RUN" 0 "${settings[@]}"
  sed "s/^/BOOT $A /" "$WORK/zab-$RUN.log"
  running=$(docker inspect qwen38-flash-next-tf --format '{{.Config.Image}}' 2>/dev/null)
  if ! curl -sf -m 5 -o /dev/null "http://127.0.0.1:$PORT/health"; then
    echo "BOOT $A FAILED: /health does not answer"; return 1
  fi
  if [ "$running" != "$image" ]; then
    echo "BOOT $A FAILED: the serve runs $running, not $image"; return 1
  fi
  python3 "$WORK/zgold_cmp.py" "$GOLDEN_REF" "$WORK/zgold-$RUN.json" > "$WORK/zgold-$RUN.cmp" 2>&1
  local gold=$?
  { cat "$WORK/zgold-$RUN.cmp"; echo "exit $gold"; } | sed "s/^/GOLD $A /"
  if [ "$gold" != 0 ]; then
    echo "== $(now) ARM $A golden not identical: no speed result (TTFT and RigMark skipped)"; return 1
  fi
  for th in false true; do
    curl -sN -m 120 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Say hello.\"}], \"max_tokens\": 6, \"temperature\": 0, \"stream\": true, \"chat_template_kwargs\": {\"enable_thinking\": $th}}" \
      | head -c 6000 | sed "s/^/SHAPE $A thinking=$th /"
  done
  # shellcheck disable=SC2086  # TTFT_ARGS is a list of options
  { python3 "$HERE/ttft.py" "$PORT" --reps "$TTFT_REPS" $TTFT_ARGS 2>&1; echo "exit $?"; } | sed "s/^/TTFT $A /"
  if [ "$RIGMARK" = 1 ]; then
    { python3 "$HERE/effort_check.py" "$PORT" "$EXTRA" 2>&1; echo "exit $?"; } | sed "s/^/EFFORT $A /"
    RIGMARK_OTS_PATCHES="$patches" bash "$HERE/rigmark_run.sh" "$RUN" "$RIGMARK_ID" "$tpl" "$EXTRA" 2>&1 \
      | sed "s/^/RIGMARK $A /"
  fi
  echo "== $(now) ARM $A done"
}

if [ "${1:-}" = --arm ]; then
  shift
  RIGMARK_ID=${RIGMARK_ID:?}
  arm "$@"
  exit $?
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
