#!/bin/bash
# test_rigmark_dryrun.sh <rigmark clone at the pinned commit>   CPU, no GPU, no serve, no docker: the RigMark tooling
# end to end against rigmark_fake_serve.py (beside this script: the Zig server's routes and stream shape, or the
# Python server's in its python modes) on a free local port, stand-ins for `docker` (a serving container described as
# the Zig serve's or, with ENGINE=python in $W/state, the Python serve's: args, env, labels, mounts, image ids; the
# arm in $W/state; `docker exec` runs the fake's --probe), `nvidia-smi` (one GB10 unless FAKE_GPUS says otherwise),
# ~/work/zarm.sh (a "boot" restarts the fake serve, which empties its prompt cache, and writes the arm's golden file),
# the Python recipe's start.sh / stop.sh, the Zig recipe's stop.sh and ~/work/qf_harness.py (golden replies), and
# RigMark's own runner (a short suite: RIGMARK_ARGS). Checks, each an ok / FAIL line:
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
#      for ours and exits 1 (DIFF);
#   6. the Python engine: the python stock / ours templates each pass on their own container (revision from the
#      mounted cache's refs/main, the SSD n-gram reader, the image's tf.ots-patches) and are refused on the other's, on
#      a Zig container (engine), with another KV dtype, with another --mtp-drafts (serve arguments); a Zig template is
#      refused on a Python container; effort_check.py passes on the Python server (no /tokenize: the in-container
#      probe + the live prompt count) and fails on one that drops reasoning_effort; RigMark's prefill on it is refused
#      (no /tokenize) unless --skip-prefill;
#   7. zab_rm.sh end to end with ENGINE=python arms (stock base, production ours): the Zig serve stopped, the Python
#      recipe booted with its own kernel cache, the python templates chosen, the golden reference created from the
#      stock arm's boot and named as a python self-reference, both arms 6/6 against it, RigMark with --skip-prefill,
#      EFFORT OK, the serve stopped after each arm; zab_rm_sum.py exits 0; a second sweep does not recreate the
#      reference; a Python arm whose replies differ from it runs no speed probes and exits 1 (DIFF).
# Prints "all passed" or "FAILED n"; exit = failures.
set -u
RM=$(cd "${1:?rigmark clone}" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd); BENCH=$(cd "$HERE/.." && pwd); ZIG=$(cd "$BENCH/.." && pwd)
W=$(mktemp -d "${TMPDIR:-$HOME}/rmdry-XXXX") || exit 1
trap '[ -f "$W/fake.pid" ] && kill "$(cat "$W/fake.pid")" 2>/dev/null; rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
mkdir -p "$W/bin" "$W/work/zab3" "$W/out" "$W/zab" "$W/qwen-py" "$W/qwen-zig" \
  "$W/hf/hub/models--Vontra--Qwen3.8-Flash-Next-MLX-4bit-MTP/refs"
printf 2b170fa6309d5d1ee380b35636075fac7945f286 > "$W/hf/hub/models--Vontra--Qwen3.8-Flash-Next-MLX-4bit-MTP/refs/main"
cat > "$W/bin/docker" <<'EOF'
#!/bin/bash
# the stand-in docker: one running container on $FAKE_PORT, the recipe's Zig serve or (ENGINE=python in the state)
# its Python serve; its image and settings from $W/state (line 1: the image tag; then the arm's settings: the
# TF_FLASHNEXT_* / TENSORFOLD_* ones become env, MTP_DRAFTS / KV_DTYPE serve arguments)
STATE="$FAKE_W/state"; IMAGE=$(head -1 "$STATE")
set_of() { tail -n +2 "$STATE" | grep -m1 "^$1=" | cut -d= -f2-; }
id_of() {   # an image tag -> its id (an id stays itself)
  case "$1" in sha256:*) echo "$1" ;; tensorfold-qwen38:zig-db28187) echo sha256:570c4 ;;
    tensorfold-qwen38:v0.6.1) echo sha256:b859e ;; tensorfold-qwen38:v061-ots) echo sha256:8e4a7 ;;
    *) echo "sha256:0750$(printf %s "$1" | md5sum | cut -c1-8)" ;; esac
}
BAKED='"TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121", "TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python"'
case "${3:-}" in tensorfold-qwen38:v0.6.1|tensorfold-qwen38:v061-ots|sha256:b859e|sha256:8e4a7)
  BAKED='"HF_HOME=/root/.cache/huggingface"' ;; esac
RECIPE='"TENSORFOLD_CUDA_KERNELS=/root/.cache/tensorfold/kernels", "TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python", "TENSORFOLD_IMAGE_TOKENS=16384", "TENSORFOLD_MAX_IMAGES=50", "TENSORFOLD_MEMORY_RESERVE_GIB=10", "TENSORFOLD_NO_UPDATE_CHECK=1", "TENSORFOLD_VIDEO_TOKENS=16384", "TENSORFOLD_VISION_WORKSPACE_MIB=2048", "TF_FLASHNEXT_DEPTH=15", "TF_FLASHNEXT_PREFILL_TAIL=512", "TF_FLASHNEXT_PRODUCT_STREAMS=2", "TF_FLASHNEXT_YARN=0"'
PYRECIPE='"HF_HOME=/root/.cache/huggingface", "TENSORFOLD_IMAGE_TOKENS=16384", "TENSORFOLD_MEMORY_RESERVE_GIB=2", "TENSORFOLD_MTP_COPY=1", "TENSORFOLD_NO_UPDATE_CHECK=1", "TENSORFOLD_PREFILL_ROWS=2048", "TENSORFOLD_VIDEO_TOKENS=16384", "TENSORFOLD_VISION_WORKSPACE_MIB=0"'
EXTRA=$(tail -n +2 "$STATE" | grep -E '^(TF_FLASHNEXT_|TENSORFOLD_)' | sed 's/.*/, "&"/' | tr -d '\n')
case "$1" in
  ps) echo fakeserve ;;
  image) [ "$2" = inspect ] && echo "[{\"Id\": \"$(id_of "$3")\", \"Config\": {\"Env\": [$BAKED, \"PATH=/usr/bin\"]}}]" ;;
  exec) shift; [ "$1" = fakeid ] || { echo "no container $1" >&2; exit 1; }
        python3 "$FAKE_SERVE" --probe "${@: -5}" ;;
  inspect)
    if [ "${3:-}" = --format ]; then echo "$IMAGE"; exit 0; fi
    if grep -qx ENGINE=python "$STATE"; then
      ots=""; [ "$IMAGE" = tensorfold-qwen38:v061-ots ] && ots=', "tf.ots-patches": "tensorfold-pr319-v061,ple-cache,ple-native,chain-stop,mtp-graph,ple-defer,tokenize-nogil"'
      cat <<JSON
[{"Id": "fakeid", "Image": "$(id_of "$IMAGE")", "Args": ["tensorfold", "serve", "Vontra/Qwen3.8-Flash-Next-MLX-4bit-MTP",
  "--host", "0.0.0.0", "--port", "$FAKE_PORT", "--name", "Qwen3.8-Flash-Next", "--parallel", "5", "--context", "262144",
  "--kv-dtype", "$(set_of KV_DTYPE | grep . || echo int8)", "--mtp-drafts", "$(set_of MTP_DRAFTS | grep . || echo 6)",
  "--mtp-confidence", "0.60", "--temperature", "1.0", "--top-p", "0.95", "--top-k", "20", "--max-tokens", "32768",
  "--ple-on-ssd", "--vision", "--vision-max-images", "50", "--thinking"],
  "Mounts": [{"Type": "bind", "Source": "$FAKE_W/hf", "Destination": "/root/.cache/huggingface"}],
  "Config": {"Image": "$IMAGE", "Env": ["HF_HUB_OFFLINE=1", $PYRECIPE$EXTRA, "PATH=/usr/bin"],
    "Labels": {"tf.patches": "797af1d9df4d"$ots}}}]
JSON
      exit 0
    fi
    cat <<JSON
[{"Id": "fakeid", "Image": "$(id_of "$IMAGE")", "Args": ["tensorfold-native", "serve",
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
cat > "$W/qwen-py/start.sh" <<'EOF'
#!/bin/bash
# the stand-in Python recipe start.sh [restart]: settings from the environment as the recipe's config.sh reads them
# (IMAGE, MTP_DRAFTS, KV_DTYPE, every TENSORFOLD_*); "boots" the fake serve in FAKE_PYMODE (default python), records
# the container in $FAKE_W/state, the golden mode (FAKE_GOLD) for the qf_harness stand-in and the KERNEL_CACHE it got
{ echo "${IMAGE:-tensorfold-qwen38:v0.6.1}"; echo ENGINE=python
  [ -n "${MTP_DRAFTS:-}" ] && echo "MTP_DRAFTS=$MTP_DRAFTS"; [ -n "${KV_DTYPE:-}" ] && echo "KV_DTYPE=$KV_DTYPE"
  env | grep -E '^TENSORFOLD_' | sort; } > "$FAKE_W/state"
echo "${FAKE_GOLD:-same}" > "$FAKE_W/goldmode"; echo "${KERNEL_CACHE:-unset}" > "$FAKE_W/kernel_cache"
[ -f "$FAKE_W/fake.pid" ] && kill "$(cat "$FAKE_W/fake.pid")" 2>/dev/null && sleep 0.3
setsid python3 "$FAKE_SERVE" "$FAKE_PORT" "${FAKE_PYMODE:-python}" </dev/null >/dev/null 2>&1 & echo $! > "$FAKE_W/fake.pid"
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$FAKE_PORT/health" && break; sleep 0.1; done
echo "[start.sh] Server answered after 1s"
EOF
cat > "$W/qwen-py/stop.sh" <<'EOF'
#!/bin/bash
[ -f "$FAKE_W/fake.pid" ] && kill "$(cat "$FAKE_W/fake.pid")" 2>/dev/null; rm -f "$FAKE_W/fake.pid"
echo "[stop.sh] Stopped and removed qwen38-flash-next-tf (python stand-in)"
EOF
cat > "$W/qwen-zig/stop.sh" <<'EOF'
#!/bin/bash
[ -f "$FAKE_W/fake.pid" ] && kill "$(cat "$FAKE_W/fake.pid")" 2>/dev/null; rm -f "$FAKE_W/fake.pid"
echo "[stop.sh] Stopped and removed qwen38-flash-next-tf (zig stand-in)"; echo zig-stopped >> "$FAKE_W/zig_stops"
EOF
cat > "$W/work/qf_harness.py" <<'EOF'
# the stand-in qf_harness.py golden <file>: six Python-engine replies (not the Zig reference's), one changed when the
# boot's FAKE_GOLD was diff
import json, os, sys
g = [{"id": f"golden-{i}", "sha": f"p{i}"} for i in range(6)]
if open(os.path.join(os.environ["FAKE_W"], "goldmode")).read().strip() == "diff":
    g[1]["sha"] = "changed"
json.dump(g, open(sys.argv[2], "w"))
print("golden-5: 8 tok (stand-in)")
EOF
cat > "$W/work/qf_run.py" <<'EOF'
# the stand-in qf_run.py <label> <out.jsonl> decode: rows as qf_run.py writes them (one per request, RUNS=1) at a
# known client-side rate ((512 - 1) / (elapsed - ttft)), and its summary lines (engine decode_s: 0.0 here, as on Zig)
import json, os, sys
assert sys.argv[3] == "decode" and os.environ.get("RUNS") == "1", sys.argv
with open(sys.argv[2], "a") as f:
    for kind, base in (("prose", 70.0), ("code", 90.0)):
        for c in (1, 2, 4):
            for _ in range(c):
                f.write(json.dumps({"label": sys.argv[1], "kind": kind, "clients": c, "run": 0,
                                    "completion_tokens": 512, "ttft": 0.1, "elapsed": 0.1 + 511 / (base / c)}) + "\n")
            print(f"{sys.argv[1]} {kind} C={c} run0: 0.0 tok/s med")
EOF
cp "$ZIG/../zig_sum.py" "$W/work/zig_sum.py"
mkdir -p "$W/work/merge/v"
cat > "$W/work/merge/v/pmz.py" <<'EOF'
# the stand-in pmz.py LABEL OUT.jsonl py (PM_N=6): six one-client prose lines
import os, sys
assert sys.argv[3] == "py" and os.environ.get("PM_N") == "6", sys.argv
for i in range(6):
    print(f"{sys.argv[1]} pm{i}: 512 tok, {60 + i:.1f} tok/s (wall), rounds 0 tok/rnd 0.000 ms/rnd 0.0 drafted 0 "
          f"accepted 0 sha 0123456789ab")
EOF
chmod +x "$W/bin/docker" "$W/bin/nvidia-smi" "$W/work/zarm.sh" "$W/qwen-py/start.sh" "$W/qwen-py/stop.sh" \
  "$W/qwen-zig/stop.sh"
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
  { RIGMARK_OTS_PATCHES=${RUN_OTS-zmerge5-dryrun} bash "$BENCH/rigmark_run.sh" "$2" "$3" "$4"; } 2>&1 | sed "s/^/RIGMARK $1 /" > "$W/$1.txt"
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
# 6. the Python engine: templates, effort, RigMark's prefill
PY_STOCK_TPL="$BENCH/rigmark/metadata-python-stock.json" PY_OURS_TPL="$BENCH/rigmark/metadata-python-ours.json"
PY_OURS=(tensorfold-qwen38:v061-ots ENGINE=python MTP_DRAFTS=8 TENSORFOLD_CHAIN_RULE=cum TENSORFOLD_CHAIN_T=0.30)
boot python tensorfold-qwen38:v0.6.1 ENGINE=python
rc=$(meta_rc "$PY_STOCK_TPL"); check "python: the stock template on the Python stock container passes (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q '"model_revision": "2b170fa6309d5d1ee380b35636075fac7945f286"' "$W/m.json" \
     && grep -q 'read from SSD (--ple-on-ssd)' "$W/m.json" && grep -q '"recipe_patches": "797af1d9df4d"' "$W/m.json" \
     && grep -q '"ots_patches": "none' "$W/m.json" && grep -q 'requests_running 0' "$W/m.json" \
     && grep -q 'up to --mtp-drafts 6' "$W/m.json" && ! grep -q '/root\|"expect"\|FILLED PER RUN' "$W/m.json"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/m.out"
rc=$(meta_rc "$PY_OURS_TPL"); check "python: the ours template on the Python stock container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q "template's image is tensorfold-qwen38:v061-ots" "$W/m.out"; echo $?)"
rc=$(meta_rc "$STOCK_TPL"); check "python: a Zig template on a Python container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'for the zig engine, the container runs python' "$W/m.out"; echo $?)"
boot python tensorfold-qwen38:v0.6.1 ENGINE=python MTP_DRAFTS=8
rc=$(meta_rc "$PY_STOCK_TPL"); check "python: the stock image with another --mtp-drafts is not stock (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'serve arguments differ' "$W/m.out"; echo $?)"
boot python tensorfold-qwen38:v0.6.1 ENGINE=python KV_DTYPE=bf16
rc=$(meta_rc "$PY_STOCK_TPL"); check "python: another KV dtype is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q "KV cache is int8, the container runs --kv-dtype bf16" "$W/m.out"; echo $?)"
boot python "${PY_OURS[@]}"
rc=$(meta_rc "$PY_OURS_TPL"); check "python: the ours template on the production container passes (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q '"ots_patches": "tensorfold-pr319-v061,ple-cache' "$W/m.json" \
     && grep -q 'chain rule TENSORFOLD_CHAIN_RULE cum at TENSORFOLD_CHAIN_T 0.30' "$W/m.json" \
     && grep -q '"TENSORFOLD_CHAIN_T": "0.30"' "$W/m.json"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/m.out"
rc=$(meta_rc "$PY_STOCK_TPL"); check "python: the stock template on the production container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'not stock' "$W/m.out"; echo $?)"
boot python tensorfold-qwen38:v061-ots ENGINE=python MTP_DRAFTS=8 TENSORFOLD_CHAIN_RULE=conf TENSORFOLD_CHAIN_T=0.30
rc=$(meta_rc "$PY_OURS_TPL"); check "python: the ours template with another chain rule is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q "template's env differs" "$W/m.out"; echo $?)"
boot python tensorfold-qwen38:v061-ots ENGINE=python TENSORFOLD_CHAIN_RULE=cum TENSORFOLD_CHAIN_T=0.30
rc=$(meta_rc "$PY_OURS_TPL"); check "python: the ours template with the recipe's --mtp-drafts 6 is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q "template's serve arguments are" "$W/m.out"; echo $?)"
boot zig tensorfold-qwen38:zig-db28187
rc=$(meta_rc "$PY_STOCK_TPL"); check "python: a python template on a Zig container is refused (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'for the python engine, the container runs zig' "$W/m.out"; echo $?)"
boot python tensorfold-qwen38:v0.6.1 ENGINE=python
python3 "$BENCH/effort_check.py" "$FAKE_PORT" > "$W/eff.out" 2>&1; rc=$?
check "python: effort_check.py passes (no /tokenize; probe + live prompt count) (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q 'App._prepare in the serving container' "$W/eff.out" \
     && grep -q '^effort OK' "$W/eff.out"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/eff.out"
boot python-noeffort tensorfold-qwen38:v0.6.1 ENGINE=python
python3 "$BENCH/effort_check.py" "$FAKE_PORT" > "$W/eff2.out" 2>&1; rc=$?
check "python: a server that drops reasoning_effort fails effort_check.py (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q "live reply's prompt has" "$W/eff2.out"; echo $?)"
boot python tensorfold-qwen38:v0.6.1 ENGINE=python
rc=$(RUN_OTS="" run p dry-p cid-py "$PY_STOCK_TPL")
check "python: RigMark's token-id prefill is refused by the Python server (exit $rc)" \
  "$([ "$rc" != 0 ] && grep -aq 'tokenize\|404' "$W/p.txt" && grep -q 'rigmark_meta: .*stock' "$W/p.txt"; echo $?)"
boot python tensorfold-qwen38:v0.6.1 ENGINE=python
rc=$(RUN_OTS="" RIGMARK_ARGS="$RIGMARK_ARGS --skip-prefill" run q dry-q cid-py "$PY_STOCK_TPL")
check "python: with --skip-prefill RigMark runs clean (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -aq '^RIGMARK q summary {.*"prefill":{}' "$W/q.txt"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/q.txt"
# 7. zab_rm.sh with ENGINE=python arms
export ZIG_RECIPE="$W/qwen-zig" PY_RECIPE="$W/qwen-py" PY_KERNEL_CACHE="$W/kc-py"
PYREF="$W/work/zab3/zgold-python-stock.json"
PY_OURS_SPEC="ENGINE=python PREPARE=0 IMAGE=tensorfold-qwen38:v061-ots MTP_DRAFTS=8 TENSORFOLD_CHAIN_RULE=cum TENSORFOLD_CHAIN_T=0.30"
boot zig tensorfold-qwen38:zig-db28187; rm -f "$W/zig_stops"
bash "$BENCH/zab_rm.sh" py1 "ENGINE=python PREPARE=0" "$PY_OURS_SPEC"
PLOG="$W/zab/zabrm-py1.log"
grep -q 'ARM base lock held: engine python PREPARE=0 (metadata metadata-python-stock.json)' "$PLOG" \
  && grep -q 'ARM ours lock held: engine python .*MTP_DRAFTS=8.*(metadata metadata-python-ours.json)' "$PLOG"
check "zab_rm.sh python: base on the python stock template, ours on the python ours template" $?
[ -s "$W/zig_stops" ] && [ "$(cat "$W/kernel_cache")" = "$W/kc-py" ]
check "zab_rm.sh python: the Zig serve stopped first; the Python recipe got its own kernel cache" $?
grep -q "^GOLD base reference created from this boot: $PYREF" "$PLOG" && [ -f "$PYREF" ] \
  && grep -q "^GOLD ours reference $PYREF (python self-reference" "$PLOG" \
  && grep -q '^GOLD ours .*: 6/6 identical to' "$PLOG"
check "zab_rm.sh python: the reference is the stock arm's first boot, ours is checked against it" $?
for t in "SHAPE ours thinking=true data:" "TTFT base sample" "TTFT ours sample" "EFFORT base effort OK" \
         "EFFORT ours effort OK" "RIGMARK base note: --skip-prefill" "RIGMARK ours exit 0" "RIGMARK base exit 0" \
         "STOP base" "STOP ours" "DECODE base zrm-py1-base-p1 prose C=1 run0:" "DECODE ours exit 0" \
         "DECODE ours pass 1 /metrics:" "PM base zrm-py1-base pm5:" "PM ours exit 0"; do
  grep -q "^$t" "$PLOG"; check "zab_rm.sh python: log has '$t'" $?
done
[ ! -f "$W/fake.pid" ] && ! curl -s -o /dev/null -m 2 "http://127.0.0.1:$FAKE_PORT/health"
check "zab_rm.sh python: no serve is left running after the sweep" $?
python3 "$BENCH/zab_rm_sum.py" "$PLOG" > "$W/pz.out" 2>&1; rc=$?
check "zab_rm_sum.py python: golden MATCH against the python self-reference, sections, exit 0 (exit $rc)" \
  "$([ "$rc" = 0 ] && grep -q 'golden base: 6/6 MATCH (against .*python self-reference' "$W/pz.out" \
     && grep -q 'golden ours: 6/6 MATCH (against .*python self-reference' "$W/pz.out" \
     && grep -q 'cold prefill skipped' "$W/pz.out" \
     && grep -q 'decode ours: prose C1/C2/C4 70.0 / 35.0 / 17.5; code C1/C2/C4 90.0 / 45.0 / 22.5; pm prose C1 62.5 (n6)' \
        "$W/pz.out"; echo $?)"
[ "$rc" = 0 ] || sed 's/^/     /' "$W/pz.out"
TTFT=0 RIGMARK=0 TTFT_ARGS="--sizes 1k --thinking off --loads idle --warm-add 0" bash "$BENCH/zab_rm.sh" py2 \
  "ENGINE=python PREPARE=0" "$PY_OURS_SPEC FAKE_GOLD=diff" 2>/dev/null
PLOG2="$W/zab/zabrm-py2.log"
! grep -q 'reference created' "$PLOG2" && grep -q '^GOLD base .*: 6/6 identical to' "$PLOG2"
check "zab_rm.sh python: a second sweep keeps the reference (not recreated) and the stock arm matches it" $?
grep -q '^DECODE base exit 0' "$PLOG2" && ! grep -q '^TTFT base' "$PLOG2"
check "zab_rm.sh python: TTFT=0 skips ttft.py; the decode probes still run" $?
grep -q 'ARM ours golden not identical: no speed result' "$PLOG2" && ! grep -q '^TTFT ours\|^SHAPE ours' "$PLOG2" \
  && grep -q '^STOP ours' "$PLOG2"
check "zab_rm.sh python: replies that differ from the reference run no speed probes; the serve is still stopped" $?
python3 "$BENCH/zab_rm_sum.py" "$PLOG2" > "$W/pz2.out" 2>&1; rc=$?
check "zab_rm_sum.py python: DIFF, exit 1 (exit $rc)" \
  "$([ "$rc" = 1 ] && grep -q 'golden ours: 5/6 DIFF' "$W/pz2.out"; echo $?)"
rm -f "$PYREF"
RIGMARK=0 TTFT_ARGS="--sizes 1k --thinking off --loads idle --warm-add 0" bash "$BENCH/zab_rm.sh" py3 - \
  "$PY_OURS_SPEC" 2>/dev/null
PLOG3="$W/zab/zabrm-py3.log"
[ ! -f "$PYREF" ] && ! grep -q 'reference created' "$PLOG3" && grep -q '^GOLD ours no reference file' "$PLOG3" \
  && grep -q 'ARM ours golden not identical: no speed result' "$PLOG3"
check "zab_rm.sh python: only a Python stock arm creates the reference; ours without one has no speed result" $?
[ $fails = 0 ] && echo "all passed" || echo "FAILED $fails"
exit $fails
