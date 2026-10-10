#!/bin/bash
# test_rigmark_dryrun.sh <rigmark clone at the pinned commit>   CPU, no GPU, no serve, no docker: the RigMark tooling
# end to end against rigmark_fake_serve.py (beside this script: the Zig server's routes and stream shape) on a free
# local port, stand-ins for `docker` (a serving container described as the Zig serve's: args, env, labels, image ids;
# the arm in $W/state), `nvidia-smi` (one GB10 unless FAKE_GPUS says otherwise) and ~/work/zarm.sh (a "boot" restarts
# the fake serve, which empties its prompt cache, and writes the arm's golden file), and RigMark's own runner (a short
# suite: RIGMARK_ARGS). Checks, each an ok / FAIL line:
#   1. the Zig server's cache rules (mode zig: completion token-id prompts keep no state, cache_salt not read): a run
#      exits 0 with a receipt, a card and a summary line, its immediate-replay rows report 0 cached tokens (as spark6's
#      live receipts do); a second run of the same comparison ID on the same boot exits 0 too;
#   2. a serve that keeps every prompt and ignores cache_salt (mode keepall): a second run of one comparison ID on one
#      boot is refused by RigMark (a cold sample reported cached), non-zero, its receipt kept with an "error"; after a
#      restart it runs clean; a serve that honours cache_salt (mode honour): two runs on one boot both exit 0;
#   3. metadata: the ours template on an OTS container is filled (image, revision, patch set, tf_env, no
#      "FILLED PER RUN", no "expect" block, no directory paths); the stock template on the stock container passes; the
#      stock template on an OTS container, the ours template on the stock container, and two GPUs are each refused;
#   4. summaries: rigmark_sum.py report on two arms parses and exits 0; a refused run is a RigMark ERROR, exit 1;
#   5. zab_rm.sh end to end (stock base, OTS ours with PATCHES=): both arms boot under the lock, golden 6/6, SHAPE,
#      TTFT, EFFORT and RIGMARK lines, the stock / ours templates chosen; zab_rm_sum.py prints golden MATCH, the TTFT
#      and RigMark sections (one sweep) and exits 0; the same with ours's golden replies changed runs no speed probes
#      for ours and exits 1 (DIFF).
# Prints "all passed" or "FAILED n"; exit = failures.
set -u
RM=$(cd "${1:?rigmark clone}" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd); BENCH=$(cd "$HERE/.." && pwd); ZIG=$(cd "$BENCH/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME}/rmdry-XXXX") || exit 1
trap '[ -f "$W/fake.pid" ] && kill "$(cat "$W/fake.pid")" 2>/dev/null; rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
mkdir -p "$W/bin" "$W/work/zab3" "$W/out" "$W/zab"
cat > "$W/bin/docker" <<'EOF'
#!/bin/bash
# the stand-in docker: one running container, the recipe's Zig serve on $FAKE_PORT, its image and env from $W/state
# (line 1: the image tag; then TF_FLASHNEXT_* / TENSORFOLD_* settings the arm added)
STATE="$FAKE_W/state"; IMAGE=$(head -1 "$STATE")
id_of() {   # an image tag -> its id (an id stays itself)
  case "$1" in sha256:*) echo "$1" ;; tensorfold-qwen38:zig-db28187) echo sha256:570c4 ;;
    *) echo "sha256:0750$(printf %s "$1" | md5sum | cut -c1-8)" ;; esac
}
BAKED='"TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121", "TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python"'
RECIPE='"TENSORFOLD_CUDA_KERNELS=/root/.cache/tensorfold/kernels", "TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python", "TENSORFOLD_IMAGE_TOKENS=16384", "TENSORFOLD_MAX_IMAGES=50", "TENSORFOLD_MEMORY_RESERVE_GIB=10", "TENSORFOLD_NO_UPDATE_CHECK=1", "TENSORFOLD_VIDEO_TOKENS=16384", "TENSORFOLD_VISION_WORKSPACE_MIB=2048", "TF_FLASHNEXT_DEPTH=15", "TF_FLASHNEXT_PREFILL_TAIL=512", "TF_FLASHNEXT_PRODUCT_STREAMS=2", "TF_FLASHNEXT_YARN=0"'
EXTRA=$(tail -n +2 "$STATE" | sed 's/.*/, "&"/' | tr -d '\n')
case "$1" in
  ps) echo fakezig ;;
  image) [ "$2" = inspect ] && echo "[{\"Id\": \"$(id_of "$3")\", \"Config\": {\"Env\": [$BAKED, \"PATH=/usr/bin\"]}}]" ;;
  inspect)
    if [ "${3:-}" = --format ]; then echo "$IMAGE"; exit 0; fi
    cat <<JSON
[{"Image": "$(id_of "$IMAGE")", "Args": ["tensorfold-native", "serve",
  "/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd",
  "--name", "Qwen3.8-Flash-Next", "--host", "0.0.0.0", "--port", "$FAKE_PORT", "--context", "262144", "--parallel", "8",
  "--max-tokens", "32768", "--temperature", "1.0", "--top-p", "0.95", "--top-k", "20", "--thinking", "--kv-dtype", "fp8",
  "--vision"],
  "Config": {"Image": "$IMAGE", "Env": ["HF_HUB_OFFLINE=1", $RECIPE$EXTRA, "PATH=/usr/bin"],
    "Labels": {"tf.patches": "4144696f21e3", "tf.kernels": "present"}}}]
JSON
  ;;
esac
EOF
cat > "$W/bin/nvidia-smi" <<'EOF'
#!/bin/bash
for _ in $(seq "${FAKE_GPUS:-1}"); do echo "NVIDIA GB10, 580.178.04"; done
EOF
cat > "$W/work/zarm.sh" <<'EOF'
#!/bin/bash
# the stand-in zarm.sh LABEL PASSES [VAR=VALUE ...]: "boots" the arm (restarts the fake serve: an empty prompt cache;
# records its image and settings in $FAKE_W/state) and writes its golden file (changed when FAKE_GOLD=diff is set)
LABEL=$1; shift 2
image=tensorfold-qwen38:zig-db28187; extra=(); gold=same
for kv in "$@"; do
  case "$kv" in
    IMAGE=*) image=${kv#IMAGE=} ;;
    FAKE_GOLD=*) gold=${kv#FAKE_GOLD=} ;;
    TF_FLASHNEXT_*|TENSORFOLD_*) extra+=("$kv") ;;
  esac
done
{ echo "$image"; printf '%s\n' "${extra[@]}" | grep . ; } > "$FAKE_W/state"
[ -f "$FAKE_W/fake.pid" ] && kill "$(cat "$FAKE_W/fake.pid")" 2>/dev/null && sleep 0.3
setsid python3 "$FAKE_SERVE" "$FAKE_PORT" zig </dev/null >/dev/null 2>&1 & echo $! > "$FAKE_W/fake.pid"
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$FAKE_PORT/health" && break; sleep 0.1; done
python3 - "$FAKE_W/work/zab3/zgold-base-c1.json" "$FAKE_W/work/zgold-$LABEL.json" "$gold" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
if sys.argv[3] == "diff":
    g[1]["sha"] = "changed"
json.dump(g, open(sys.argv[2], "w"))
PY
echo "=== $LABEL start (stand-in) env: $*" > "$FAKE_W/work/zab-$LABEL.log"
echo "$image" >> "$FAKE_W/work/zab-$LABEL.log"
EOF
chmod +x "$W/bin/docker" "$W/bin/nvidia-smi" "$W/work/zarm.sh"
cp "$ZIG/zgold_cmp.py" "$W/work/zgold_cmp.py"
python3 -c 'import json, sys; json.dump([{"id": f"golden-{i}", "sha": f"s{i}"} for i in range(6)], open(sys.argv[1], "w"))' \
  "$W/work/zab3/zgold-base-c1.json"
export PATH="$W/bin:$PATH" FAKE_W="$W" FAKE_SERVE="$HERE/rigmark_fake_serve.py"
export FAKE_PORT=$(( 20000 + $$ % 20000 )) PORT
PORT=$FAKE_PORT
export RIGMARK_DIR="$RM" RIGMARK_OUT="$W/out"
export RIGMARK_ARGS="--runs 2 --prefill-depths 128,256 --prefill-runs 2 --concurrency 1,2 --concurrency-runs 1"
OURS_TPL="$BENCH/rigmark/metadata-zig-ours.json" STOCK_TPL="$BENCH/rigmark/metadata-zig-stock.json"
boot() {   # mode image [settings...]: restart the fake serve in <mode> with the container described as <image>
  local mode=$1; shift
  [ -f "$W/fake.pid" ] && kill "$(cat "$W/fake.pid")" 2>/dev/null && sleep 0.3
  printf '%s\n' "$@" > "$W/state"
  setsid python3 "$HERE/rigmark_fake_serve.py" "$FAKE_PORT" "$mode" </dev/null >/dev/null 2>&1 & echo $! > "$W/fake.pid"
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$FAKE_PORT/health" && return 0; sleep 0.1; done
  echo "FAIL the fake serve did not start"; exit 1
}
run() {   # arm label cid template -> $W/<arm>.txt (RIGMARK <arm> lines, as the harnesses log them)
  { RIGMARK_OTS_PATCHES=zmerge5-dryrun bash "$BENCH/rigmark_run.sh" "$2" "$3" "$4"; } 2>&1 | sed "s/^/RIGMARK $1 /" > "$W/$1.txt"
  grep -a "^RIGMARK $1 exit" "$W/$1.txt" | awk '{print $4}'
}
OTS=(tensorfold-qwen38:zmerge5 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15)
boot zig "${OTS[@]}"
rc=$(run a dry-a cid-zig "$OURS_TPL")
check "zig: a run exits 0 (exit $rc)" "$([ "$rc" = 0 ]; echo $?)"
grep -aq '^RIGMARK a summary {' "$W/a.txt"; check "zig: the run prints a summary line" $?
grep -aq '^RIGMARK a card ' "$W/a.txt" && [ -f "$(grep -a '^RIGMARK a card ' "$W/a.txt" | awk '{print $4}')" ]
check "zig: the run saves its card" $?
grep -aq '"extra_body":{"reasoning_effort":"low"}' "$W/a.txt"; check "the default extra body is {\"reasoning_effort\": \"low\"}" $?
grep -aq '^RIGMARK a summary {.*"replay_cached_min":0' "$W/a.txt" && \
  ! grep -aq '^RIGMARK a summary {.*"replay_cached_min":[1-9]' "$W/a.txt"
check "zig: the immediate replay reports 0 cached tokens at every depth" $?
rc=$(run f dry-f cid-zig "$OURS_TPL")
check "zig: a second run of the same comparison ID on one boot also exits 0 (exit $rc)" "$([ "$rc" = 0 ]; echo $?)"
boot keepall "${OTS[@]}"
rc=$(run g dry-g cid-keepall "$OURS_TPL")
check "keepall: the first run exits 0 (exit $rc)" "$([ "$rc" = 0 ]; echo $?)"
rc=$(run b dry-b cid-keepall "$OURS_TPL")
check "keepall: a second run of the same comparison ID on one boot is refused (exit $rc)" "$([ "$rc" != 0 ]; echo $?)"
grep -aq 'cached tokens' "$W/b.txt"; check "keepall: the refusal is RigMark's cold-cache check" $?
grep -aq '^RIGMARK b summary {.*"error":"cold prefill' "$W/b.txt"; check "keepall: its receipt keeps the error" $?
boot keepall "${OTS[@]}"
rc=$(run e dry-e cid-keepall "$OURS_TPL")
check "keepall: after a restart the same comparison ID runs clean (exit $rc)" "$([ "$rc" = 0 ]; echo $?)"
boot honour "${OTS[@]}"
rc1=$(run c dry-c cid-honour "$OURS_TPL"); rc2=$(run d dry-d cid-honour "$OURS_TPL")
check "honour: two runs of one comparison ID both exit 0 ($rc1, $rc2)" "$([ "$rc1" = 0 ] && [ "$rc2" = 0 ]; echo $?)"
meta=$(ls "$W"/out/dry-c-*.metadata.json | head -1)
grep -q 'tensorfold-qwen38:zmerge5' "$meta" && grep -q '1464274120d36a4d8fcaa934552334a7d83ce0fd' "$meta" \
  && grep -q '"ots_patches": "zmerge5-dryrun"' "$meta" && grep -q '"TF_FLASHNEXT_CONFIDENCE": "-0.15"' "$meta" \
  && grep -q 'FP8 (TF_FLASHNEXT_MTP_FP8 overlay)' "$meta" && ! grep -q 'FILLED PER RUN' "$meta" \
  && ! grep -q '"expect"' "$meta" && ! grep -q '/root' "$meta" && ! grep -q 'TENSORFOLD_CUDA_KERNELS' "$meta" \
  && ! grep -q 'TENSORFOLD_VISION_PYTHONPATH' "$meta"
check "metadata (ours): image, revision, patch set, env filled; no FILLED / expect / paths / image ENV left" $?
meta_rc() {   # template -> rigmark_meta.py's exit code on the current stand-in container
  python3 "$BENCH/rigmark_meta.py" "$1" "$W/m.json" "$FAKE_PORT" > "$W/m.out" 2>&1; echo $?
}
rc=$(meta_rc "$STOCK_TPL"); check "metadata: the stock template on an OTS container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'not stock' "$W/m.out"; echo $?)"
boot zig tensorfold-qwen38:zig-db28187
rc=$(meta_rc "$STOCK_TPL"); check "metadata: the stock template on the stock container passes (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q '"ots_patches": "none' "$W/m.json"; echo $?)"
rc=$(meta_rc "$OURS_TPL"); check "metadata: the ours template on the stock container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'ours template on the stock serve' "$W/m.out"; echo $?)"
boot zig tensorfold-qwen38:zig-db28187 TF_FLASHNEXT_DEPTH=8
rc=$(meta_rc "$STOCK_TPL"); check "metadata: the stock image with a changed recipe setting is not stock (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'env differs' "$W/m.out"; echo $?)"
rc=$(FAKE_GPUS=2 meta_rc "$OURS_TPL"); check "metadata: two GPUs are refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'one GB10' "$W/m.out"; echo $?)"
python3 "$BENCH/rigmark_sum.py" report "$W/c.txt" "$W/d.txt" > "$W/q.out"; rc=$?
check "rigmark_sum report: two arms parse (exit $rc)" "$([ "$rc" = 0 ] && grep -q 'C2 aggregate tok/s' "$W/q.out" \
  && grep -q 'code ttft s' "$W/q.out"; echo $?)"
python3 "$BENCH/rigmark_sum.py" report "$W/g.txt" "$W/b.txt" > "$W/e.out"; rc=$?
check "rigmark_sum report: a refused run is a RigMark ERROR, exit 1 (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'RigMark ERROR b: RigMark stopped' "$W/e.out"; echo $?)"
# zab_rm.sh end to end, then its summary
export WORK="$W/work" LOCK="$W/gpu.lock" ZABRM_DIR="$W/zab" GOLDEN_REF="$W/work/zab3/zgold-base-c1.json"
export TTFT_ARGS="--sizes 1k --thinking off,on --warm-base 3k --warm-add 300 --loads idle" TTFT_REPS=1
OURS_SPEC="PREPARE=0 IMAGE=tensorfold-qwen38:zmerge5 TF_FLASHNEXT_CONFIDENCE=-0.15 PATCHES=zmerge5.patch+ots0104"
bash "$BENCH/zab_rm.sh" dry1 "PREPARE=0 IMAGE=tensorfold-qwen38:zig-db28187" "$OURS_SPEC"
ZLOG="$W/zab/zabrm-dry1.log"
grep -q 'ARM base lock held: .*(metadata metadata-zig-stock.json)' "$ZLOG" \
  && grep -q 'ARM ours lock held: .*PATCHES=zmerge5.patch+ots0104 (metadata metadata-zig-ours.json)' "$ZLOG"
check "zab_rm.sh: base on the stock template, ours on the ours template" $?
for t in "GOLD base" "GOLD ours" "SHAPE ours thinking=true data:" "TTFT base sample" "TTFT ours sample" \
         "EFFORT ours effort OK" "RIGMARK base summary" "RIGMARK ours summary" "RIGMARK ours exit 0"; do
  grep -q "^$t" "$ZLOG"; check "zab_rm.sh: log has '$t'" $?
done
grep -q '"ots_patches": "zmerge5.patch+ots0104"' "$W"/out/zrm-dry1-ours-*.metadata.json
check "zab_rm.sh: ours's PATCHES= reaches RigMark's metadata" $?
python3 "$BENCH/zab_rm_sum.py" "$ZLOG" > "$W/z.out" 2>&1; rc=$?
check "zab_rm_sum.py: golden MATCH, TTFT and RigMark sections, exit 0 (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q 'golden ours: 6/6 MATCH' "$W/z.out" && grep -q '^cold1k-off' "$W/z.out" \
     && grep -q 'comparison zrm-dry1' "$W/z.out" && grep -q 'code decode tok/s' "$W/z.out"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/z.out"
RIGMARK=0 bash "$BENCH/zab_rm.sh" dry2 - "$OURS_SPEC FAKE_GOLD=diff"
python3 "$BENCH/zab_rm_sum.py" "$W/zab/zabrm-dry2.log" > "$W/z2.out" 2>&1; rc=$?
check "zab_rm_sum.py: ours's golden replies changed: DIFF, exit 1 (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'golden ours: 5/6 DIFF' "$W/z2.out"; echo $?)"
grep -q 'ARM ours golden not identical: no speed result' "$W/zab/zabrm-dry2.log" && \
  ! grep -q '^TTFT ours\|^SHAPE ours' "$W/zab/zabrm-dry2.log"
check "zab_rm.sh: an arm whose golden replies differ runs no speed probes" $?
[ $fails = 0 ] && echo "all passed" || echo "FAILED $fails"
exit $fails
