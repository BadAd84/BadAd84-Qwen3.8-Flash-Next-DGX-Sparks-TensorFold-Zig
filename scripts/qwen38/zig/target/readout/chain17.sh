#!/usr/bin/env bash
# chain17.sh - patches 0016 (the read-outs' 12-bit blocks loaded two groups ahead) and 0017 (TF_FLASHNEXT_FUSED_SPLIT)
# on spark6: build image rq17 (the 15 patches of patches/1.2.7 plus both, from readout/p17), then one fresh boot a cell
# at fp8 KV, 262,144 tokens for 1, 2 and 4 streams and the shared page pool (TF_FLASHNEXT_KV_PAGES=4096, patch 0015)
# for 6 and 8. Arms in rung order: the base, + TF_FLASHNEXT_HC_Q12=1, + TF_FLASHNEXT_FUSED_SPLIT=1; then the fused
# split alone and repeats of the base and of both at 1 and 4. Golden against stock, every decode reply's sha against
# the base arm's. Then image rq17x (the same plus v16x's kernel and expert logs, if that patch applies) and three
# kernel-log cells at one stream with expert_ids/run.sh's settings. Takes the GPU lock; restores production.
set -u
cd ~/work/target || exit 1
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
D=readout; LOG=$D/chain17.log; SUM=$D/chain17.sum
: > "$LOG"
close_window() {
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
}
klog() { # name env
  local out=bench/$1; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env $2 PREPARE=0 IMAGE=tensorfold-qwen38:rq17x CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== klog $1 env=[$2] $(date -Is)"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "$1" 1 "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-160
  close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
(
  flock -w 14400 9 || { echo "chain17: the GPU lock is held" >> "$LOG"; exit 1; }
  echo "=== lock $(date -Is)" >> "$LOG"
  # build_patches.sh labels its images tf.kernels=present; the recipe boots only `embedded` (build_rung.sh relabels)
  docker image inspect tensorfold-qwen38:rq17 > /dev/null 2>&1 \
    || bash ./build_patches.sh rq17 git://192.168.99.16/up-pr/tf "$BASE127" "$HOME/work/target/$D/p17" > "$D/build-rq17.log" 2>&1 \
    || { echo "rq17 build failed"; tail -40 "$D/build-rq17.log"; } >> "$LOG"
  bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:rq17 embedded > /dev/null 2>&1
  echo "=== built $(date -Is) tf.kernels=$(docker image inspect -f '{{index .Config.Labels "tf.kernels"}}' tensorfold-qwen38:rq17)" >> "$LOG"
  if docker image inspect tensorfold-qwen38:rq17 > /dev/null 2>&1; then
    export NORESTORE=1 KV_DTYPE=fp8 CONTEXT=262144 HOLD_FILE=none IMG=tensorfold-qwen38:rq17
    arm() { echo "=== arm $2 C=[$1] $(date -Is)" >> "$LOG"; STREAMS="$1" bash ./patcheval.sh "$2" >> "$LOG" 2>&1; }
    PG=TF_FLASHNEXT_KV_PAGES=4096
    Q=TF_FLASHNEXT_HC_Q12=1
    F=TF_FLASHNEXT_FUSED_SPLIT=1
    arm "1 2 4" "r7b:"
    arm "6 8" "r7b:$PG"
    arm "1 2 4" "r7q:$Q"
    arm "6 8" "r7q:$PG $Q"
    arm "1 2 4" "r7qf:$Q $F"
    arm "6 8" "r7qf:$PG $Q $F"
    arm "1 4" "r7f:$F"
    arm "1 4" "r7b2:"
    arm "1 4" "r7qf2:$Q $F"
  fi
  mkdir -p "$D/p17x" && cp "$D"/p17/*.patch "$D/p17x/" && cp ep/pv16x/0099-diag.patch "$D/p17x/"
  if docker image inspect tensorfold-qwen38:rq17x > /dev/null 2>&1 \
    || bash ./build_patches.sh rq17x git://192.168.99.16/up-pr/tf "$BASE127" "$HOME/work/target/$D/p17x" > "$D/build-rq17x.log" 2>&1; then
    bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:rq17x embedded > /dev/null 2>&1
    { klog rk-b ""; klog rk-q "TF_FLASHNEXT_HC_Q12=1"; klog rk-qf "TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1"; } >> "$LOG" 2>&1
  else
    { echo "rq17x build failed"; grep -a "error\|does not apply" "$D/build-rq17x.log" | head -5; } >> "$LOG"
  fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> "$LOG"
  curl -s -m 5 -o /dev/null -w "health %{http_code}\n" http://127.0.0.1:8888/health >> "$LOG"
  echo "=== restored $(date -Is)" >> "$LOG"
) 9> ~/work/gpu.lock
{
  for d in bench/pe-r7*/c*; do
    [ -f "$d/zgold.json" ] || { echo "$d: no golden"; continue; }
    echo "GOLD $d $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "$d/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]*/[0-9]* identical')"
    grep -a "self-check: \|read-outs in 12 bits\|TF_FLASHNEXT_FUSED_SPLIT\|streams at once\|error" "$d/logs.txt" 2>/dev/null | cut -c1-200 | head -4
  done
  for a in r7q r7qf; do for c in 1 2 4 6 8; do
    echo "DECODE r7b against $a c$c: $(python3 fp8cmp.py "bench/pe-r7b/c$c/dec.jsonl" "bench/pe-$a/c$c/dec.jsonl" 2>&1 | tail -1)"
  done; done
  for a in r7f r7b2 r7qf2; do for c in 1 4; do
    echo "DECODE r7b against $a c$c: $(python3 fp8cmp.py "bench/pe-r7b/c$c/dec.jsonl" "bench/pe-$a/c$c/dec.jsonl" 2>&1 | tail -1)"
  done; done
  grep -a "^=== \|^DEC\|rq17\|health" "$LOG"
} > "$SUM" 2>&1
touch "$D/CHAIN17-DONE"
