#!/usr/bin/env bash
# stage3c.sh - the read-out fusion group repaired at its own rung (overlay.py: chunk stores its position, the
# prompt's last row is recorded, the relaxed MX128 tile stays off), then the later levers on top of it:
# f0025 (read-out), f0026 (q12), f0027 (cost), f0029 (vision), f0032 (reader knob, check log).
# Decode and golden through patcheval.sh; the prompt levers are priced by cold prompt time (prefill_arm.sh), since
# a 512-token reply cannot show them.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f PROFILE-DONE ] && break; sleep 30; done
echo "=== building the repaired rungs $(date -Is)"
for K in 0025 0026 0027 0029 0032; do
  T=f$K; dir=patches126/$T
  rm -rf "$dir" && mkdir -p "$dir" && cp "rungs/$T.patch" "$dir/0001-rung-$T.patch"
  bash ./build_patches.sh "$T" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$T.log" 2>&1
  rc=$?
  echo "build $T rc=$rc $(grep -aE '^BUILT' "build-$T.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-$T.log" | sort -u | head -8 | cut -c1-180
  [ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$T" embedded > /dev/null 2>&1
done
OFF="TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=256"
echo "=== cold prompt time $(date -Is)"
bash ./prefill_arm.sh \
  "warm:up126:" "stock:up126:" "r15:rung3:" "r17:r0017:" "r19:r0019:" "r21:r0021:" \
  "r21tail0:r0021:TF_FLASHNEXT_PREFILL_TAIL=0" \
  "r21mx:r0021:TF_FLASHNEXT_PROMPT_MX128=1024" \
  "r21mxg0:r0021:TF_FLASHNEXT_PROMPT_MX128=1024 TF_FLASHNEXT_PROMPT_GEMM2=0" \
  "hcoff:f0025:$OFF" \
  "hc2:f0025:TF_FLASHNEXT_PROMPT_HC2=1 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=256" \
  "direct:f0025:TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1 TF_FLASHNEXT_HEAD_PIECE=256" \
  "piece:f0025:TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=1536" \
  "hcall:f0025:" "q12:f0026:" "cost:f0027:" "all:f0032:" "stock2:up126:" > stage3c.pf.log 2>&1
echo "=== decode and golden $(date -Is)"
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > stage3c.log
run() { # name image [env]
  local name=$1 img=$2; shift 2
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> stage3c.log; return; }
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:$*" >> stage3c.log 2>&1
}
run c3warm r0021
run c3r21 r0021
run c3hcoff f0025 "$OFF"
run c3hc f0025
run c3q12 f0026
run c3cost f0027
run c3vision f0029
run c3all f0032
run c3r21b r0021
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch STAGE3C-DONE
