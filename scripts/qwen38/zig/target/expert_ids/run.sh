#!/usr/bin/env bash
# run.sh - expert ids, passes and per-launch time on both stacks: two diag images (our 14-patch series and the
# production tree, each with the kernel log and the ids expert log), then one fresh boot an arm at 1 and 4 streams,
# a trailing request closing the kernel log's decode window; production restored at the end.
set -u
cd ~/work/target || exit 1
BASE=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
eval "$(grep '^MTP=' rfarm2.sh)"
eval "$(grep '^PE=' rfarm2.sh)"
close_window() {
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
}
ours() { # name streams
  local n=$1 c=$2 out=bench/ep-$1; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 IMAGE=tensorfold-qwen38:v16x CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=$c CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== $n ours c=$c $(date -Is)"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "ep-$n" "$c" "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  echo "kernel windows $(grep -ac '^kernel log: window' "$out/logs.txt") expert $(grep -ac '^expert log' "$out/logs.txt")"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
prod() { # name streams
  local n=$1 c=$2 out=bench/ep-$1; mkdir -p "$out"
  ( cd "$HOME/qwen-zig-prod" && env $PE IMAGE=tensorfold-qwen38:pdiagx PREPARE=0 PARALLEL=$c WAIT_TIMEOUT=3600 \
      TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_GRAPH_FAIL=1 TF_FLASHNEXT_MTP_FP8=$MTP \
      HOST=127.0.0.1 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== $n production c=$c $(date -Is)"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "ep-$n" "$c" "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  echo "kernel windows $(grep -ac '^kernel log: window' "$out/logs.txt") expert $(grep -ac '^expert log' "$out/logs.txt")"
  docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1; sleep 8
}
build() {
  rm -rf ep/tree ep/tree2 ep/pv16x ep/ptree
  mkdir -p ep/tree ep/pv16x
  ( cd ep/tree && git init -q && git remote add origin git://192.168.99.16/up-pr/tf && git fetch -q --depth 1 origin "$BASE" \
      && git checkout -q --detach FETCH_HEAD && for p in ~/work/target/ep/p127/0*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done ) || return 1
  rm -rf ep/tree/.git && cp -a ep/tree ep/tree2
  python3 ep/diag/seat.py ep/tree2 && python3 ep/diag/seat_experts.py ep/tree2 || return 1
  cp ep/p127/0*.patch ep/pv16x/
  git diff --no-index --binary ep/tree ep/tree2 | sed -e "s|a/ep/tree/|a/|g" -e "s|b/ep/tree2/|b/|g" > ep/pv16x/0099-diag.patch
  echo "diag patch files: $(grep -c '^diff --git' ep/pv16x/0099-diag.patch)"
  bash ./build_patches.sh v16x git://192.168.99.16/up-pr/tf "$BASE" ~/work/target/ep/pv16x > ep/build-v16x.log 2>&1 || { echo "v16x build failed"; tail -30 ep/build-v16x.log; return 1; }
  echo "v16x built"
  cp -a pdiagtree ep/ptree && rm -rf ep/ptree/.git
  cp ep/diag/kernel_log.zig ep/ptree/zig/src/cuda/kernel_log.zig
  python3 ep/diag/seat_experts_prod.py ep/ptree || return 1
  sed -e "s|~/work/target/pdiagtree|~/work/target/ep/ptree|" -e "s|tensorfold-qwen38:pdiag |tensorfold-qwen38:pdiagx |" \
      -e "s|tensorfold-qwen38:pdiag$|tensorfold-qwen38:pdiagx|" -e "s|BUILT tensorfold-qwen38:pdiag|BUILT tensorfold-qwen38:pdiagx|" buildpdiag.sh > ep/buildpx.sh
  grep -c pdiagx ep/buildpx.sh
  bash ep/buildpx.sh > ep/build-pdiagx.log 2>&1 || { echo "pdiagx build failed"; tail -30 ep/build-pdiagx.log; return 1; }
  echo "pdiagx built"
}
# the peer lane's runner (gwfinish.sh) waits for ep/RUN-DONE before it touches the serve
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
(
  flock -w 7200 9 || exit 1
  echo "lock $(date -Is)"
  build && { ours o1 1; prod p1 1; ours o4 4; prod p4 4; }
) > ep/run.log 2>&1 9> ~/work/gpu.lock
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> ep/run.log
curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-80 >> ep/run.log
touch ep/RUN-DONE
