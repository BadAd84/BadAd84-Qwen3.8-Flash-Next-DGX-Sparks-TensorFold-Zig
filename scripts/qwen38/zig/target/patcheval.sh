#!/usr/bin/env bash
# patcheval.sh ARM [ARM...] - evaluate our ported levers one at a time on the v1.2.6 stack.
# Each ARM is name:ENV where ENV is a space-separated knob string (an empty ENV is the baseline).
# Per arm: a fresh boot a cell at C=1 and C=4 with the target's settings (nvfp4, fp8 KV, 262,144 tokens),
# golden, one decode pass (prose then code) and the boot self-check. Output: bench/pe-<name>/c<N>/.
set -u
cd ~/work/target || exit 1
# a hold file parks the arms: a run borrowing the box between a stage's parts sets HOLD and calls with HOLD_FILE=none
while [ -f "${HOLD_FILE:-HOLD}" ]; do sleep 20; done
IMG=${IMG:-tensorfold-qwen38:stack126}
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader 2>/dev/null | tr -d ' '; }
for spec in "$@"; do
  name=${spec%%:*}; envs=${spec#*:}
  [ "$name" = "$spec" ] && envs=""
  for C in 1 4; do
    out="bench/pe-$name/c$C"; mkdir -p "$out"
    ( cd ~/work/lanes/rpr/recipe && env $envs PREPARE=0 IMAGE="$IMG" CHECKPOINT=nvfp4 VISION=0 \
        TENSORFOLD_CUDA_KERNELS=native KV_DTYPE="${KV_DTYPE:-fp8}" PARALLEL="$C" CONTEXT="${CONTEXT:-262144}" HOST=127.0.0.1 \
        TF_FLASHNEXT_MEM_LOG=1 MEM_CHECK=0 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
    echo "=== pe-$name C=$C env=[$envs] gpu $(gpu)"
    docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
    grep -a "self-check\|copy windows\|a stream at" "$out/logs.txt" | head -3 | cut -c1-150
    ( cd ~/work && python3 qf_harness.py golden "$HOME/work/target/$out/zgold.json" | tail -1 )
    python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "pe-$name-c$C" "$C" "$HOME/work/target/$out/dec.jsonl" 1 \
      2>&1 | grep -a "^DEC" | cut -c1-118
    ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  done
done
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
# NORESTORE=1: a caller running several images in a row restores the production serve once, at its own end
if [ "${NORESTORE:-0}" != 1 ]; then
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
  echo "=== production $(date -Is)"
fi
touch "$HOME/work/target/PATCHEVAL-DONE"
