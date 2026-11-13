#!/usr/bin/env bash
# run2.sh - our two arms of run.sh again, after the v16x image is given the recipe's kernel label (the first run's
# arms were refused by start.sh's tf.kernels gate); waits for the peer lane's runner to finish first.
set -u
cd ~/work/target || exit 1
echo "FROM tensorfold-qwen38:v16x" | docker build -q --label tf.kernels=embedded -t tensorfold-qwen38:v16x - > ep/relabel.log 2>&1
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
  grep -a "window self-check" "$out/logs.txt" | head -1 | cut -c1-120
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
while pgrep -f "bash \./[a-z0-9_]+\.sh" > /dev/null; do sleep 20; done
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
(
  flock -w 7200 9 || exit 1
  echo "lock $(date -Is)"
  ours o1 1
  ours o4 4
) > ep/run2.log 2>&1 9> ~/work/gpu.lock
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> ep/run2.log
curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-80 >> ep/run2.log
touch ep/RUN2-DONE
