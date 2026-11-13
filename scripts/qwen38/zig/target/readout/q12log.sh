#!/usr/bin/env bash
# q12log.sh - the kernel log of our series with the read-outs on their 12-bit copies (TF_FLASHNEXT_HC_Q12=1), one
# stream, the settings of expert_ids/run.sh's `ours` arm (image v16x, bf16 KV, 131,072, graphs eager), so its decode
# window compares row for row with bench/ep-o1. Takes ~/work/gpu.lock, restores production at the end.
set -u
cd ~/work/target || exit 1
out=bench/rq-q12; mkdir -p "$out"
close_window() {
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
}
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
(
  flock -w 7200 9 || exit 1
  echo "lock $(date -Is)"
  ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 IMAGE=tensorfold-qwen38:v16x CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== q12 ours c=1 $(date -Is)"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" rq-q12 1 "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  echo "kernel windows $(grep -ac '^kernel log: window' "$out/logs.txt"); $(grep -a 'read-outs in 12 bits' "$out/logs.txt" | head -1 | cut -c1-160)"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
) > "$out/run.log" 2>&1 9> ~/work/gpu.lock
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> "$out/run.log"
curl -s -m 5 -o /dev/null -w "health %{http_code}\n" http://127.0.0.1:8888/health >> "$out/run.log"
echo "done $(date -Is)" >> "$out/run.log"
