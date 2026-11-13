#!/usr/bin/env bash
# chain18.sh - patch 0018 (TF_FLASHNEXT_READOUT_FUSE: the read-out's reduce and act in the down's epilogue, the mix in
# the up's) on spark6, all scratch under ~/work/readout: build image rq18 (patches/1.2.7's 17 + 0018, from p18), run
# the kernel contracts of the fused split (0017) and the half tiles in it, then one fresh boot a cell at fp8 KV,
# 262,144 tokens for 1, 2 and 4 streams and the page pool (TF_FLASHNEXT_KV_PAGES=4096) for 6 and 8: the base with
# both existing switches on (HC_Q12, FUSED_SPLIT), the same plus READOUT_FUSE, repeats of both at 1 and 4, and
# READOUT_FUSE alone (its BF16 kernels at decode rows) at 1 and 4. Golden against stock, every decode reply's sha
# against the base arm's, the pool line of every 6- and 8-stream boot. Then image rq18x (plus v16x's kernel log) and
# two kernel-log cells at one stream. Waits for ~/work/gpu.lock (other lanes share it); restores production.
set -u
D=$HOME/work/readout
cd ~/work/target || exit 1
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
LOG=$D/chain18.log; SUM=$D/chain18.sum
: > "$LOG"
close_window() {
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
}
klog() { # name env
  local out=$D/bench/$1; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env $2 PREPARE=0 IMAGE=tensorfold-qwen38:rq18x CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== klog $1 env=[$2] $(date -Is)"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "$1" 1 "$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-160
  close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
build() { # tag dir
  docker image inspect "tensorfold-qwen38:$1" > /dev/null 2>&1 \
    || bash ./build_patches.sh "$1" git://192.168.99.16/up-pr/tf "$BASE127" "$2" > "$D/build-$1.log" 2>&1 \
    || { echo "$1 build failed"; grep -a "error" "$D/build-$1.log" | sort -u | head -12; return 1; }
  bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$1" embedded > /dev/null 2>&1
  echo "=== built $1 $(date -Is) tf.kernels=$(docker image inspect -f '{{index .Config.Labels "tf.kernels"}}' "tensorfold-qwen38:$1")"
}
(
  echo "=== waiting for the lock $(date -Is)"
  flock -w 28800 9 || { echo "chain18: the GPU lock is held"; exit 1; }
  echo "=== lock $(date -Is)"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
  if build rq18 "$D/p18"; then
    echo "=== kernel-contract in rq18 $(date -Is)"
    docker run --rm --gpus all --ipc=host --entrypoint sh tensorfold-qwen38:rq18 -c \
      'b=$(command -v tf-cuda-test || find / -xdev -name tf-cuda-test -type f 2>/dev/null | head -1); echo "runner: ${b:-none}"; [ -n "$b" ] || exit 3; cd "$(dirname "$b")/.." 2>/dev/null; "$b" kernel-contract "fused form" "half tiles"; echo "exit $?"' \
      2>&1 | tail -60
    export NORESTORE=1 KV_DTYPE=fp8 CONTEXT=262144 HOLD_FILE=none IMG=tensorfold-qwen38:rq18
    arm() { echo "=== arm $2 C=[$1] $(date -Is)"; STREAMS="$1" bash ./patcheval.sh "$2"; }
    PG=TF_FLASHNEXT_KV_PAGES=4096
    B="TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1"
    G=TF_FLASHNEXT_READOUT_FUSE=1
    arm "1 2 4" "r8b:$B"
    arm "6 8" "r8b:$PG $B"
    arm "1 2 4" "r8g:$B $G"
    arm "6 8" "r8g:$PG $B $G"
    arm "1 4" "r8b2:$B"
    arm "1 4" "r8g2:$B $G"
    arm "1 4" "r8gb:$G"
  fi
  mkdir -p "$D/p18x" && cp "$D"/p18/*.patch "$D/p18x/" && cp ~/work/target/ep/pv16x/0099-diag.patch "$D/p18x/"
  if build rq18x "$D/p18x"; then
    klog rk8-b "TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1"
    klog rk8-g "TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1"
  fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
  curl -s -m 5 -o /dev/null -w "health %{http_code}\n" http://127.0.0.1:8888/health
  echo "=== restored $(date -Is)"
) >> "$LOG" 2>&1 9> ~/work/gpu.lock
{
  for d in bench/pe-r8*/c*; do
    [ -f "$d/zgold.json" ] || { echo "$d: no golden"; continue; }
    echo "GOLD $d $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "$d/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]*/[0-9]* identical')"
    grep -a "self-check: \|read-outs in 12 bits\|TF_FLASHNEXT_READOUT_FUSE\|error" "$d/logs.txt" 2>/dev/null | cut -c1-160 | head -3
    grep -ao "streams at once.*GiB reserve\|stream at once.*GiB reserve\|model [0-9.]* GiB" "$d/logs.txt" 2>/dev/null | cut -c1-330 | head -2
  done
  for a in r8g r8b2 r8g2 r8gb; do for c in 1 2 4 6 8; do
    [ -f "bench/pe-$a/c$c/dec.jsonl" ] || continue
    echo "DECODE r8b against $a c$c: $(python3 fp8cmp.py "bench/pe-r8b/c$c/dec.jsonl" "bench/pe-$a/c$c/dec.jsonl" 2>&1 | tail -1 | sed 's/ (bench.*//')"
  done; done
  grep -a "^=== \|^DEC\|build failed\|error\|PASS\|FAIL\|caught\|exit \|health" "$LOG" | cut -c1-200
} > "$SUM" 2>&1
touch "$D/CHAIN18-DONE"
