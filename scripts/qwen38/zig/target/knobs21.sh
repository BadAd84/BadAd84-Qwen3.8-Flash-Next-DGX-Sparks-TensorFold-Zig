#!/usr/bin/env bash
# knobs21.sh - every switch our accepted levers carry, on and off on the accepted image, one switch an arm; then
# the copy workload rung by rung (the rows and resync levers show only there).
# The upstream recipe exports GATHER_READ=pread, DRAFT_AHEAD=1, GATHER_EARLY=1, PREFILL_TAIL=512 and PROMPT_GEMM2=1,
# so the base arm has them on and an arm states what it changes. bf16 at 131,072 for the speed arms; the kv8 lever
# is then run at fp8 on the same window and at the target's 262,144.
set -u
cd ~/work/target || exit 1
IMGTAG=${IMGTAG:-r0021}
for i in $(seq 1 1200); do [ -f "${WAIT:-STAGE2B-DONE}" ] && break; sleep 30; done
# the resync lever alone on the rows rung (old 0006), built here: no timed arm is running
if ! docker image inspect tensorfold-qwen38:r0006 > /dev/null 2>&1; then
  dir=patches126/r0006
  rm -rf "$dir" && mkdir -p "$dir" && cp rungs/r0006.patch "$dir/0001-rung-0006.patch"
  bash ./build_patches.sh r0006 git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > build-r0006.log 2>&1
  echo "build r0006 rc=$? $(grep -aE '^BUILT' build-r0006.log | head -1)" > knobs21.build.log
  bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:r0006 embedded > /dev/null 2>&1
fi
export NORESTORE=1
NGOFF="TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_DRAFT_AHEAD=0 TF_FLASHNEXT_GATHER_EARLY=0"
bash ./copy_arm.sh "warm:up126:" "stock:up126:" "rows:stack126a:" "resync:r0006:" "kv8:rung2:" "ngram:rung3:" \
  "ngoff:rung3:$NGOFF" "acc:$IMGTAG:" "accngoff:$IMGTAG:$NGOFF" "hc:g25:" "all:g32:" "stock2:up126:" > knobs21.copy.log 2>&1
KV_DTYPE=bf16 CONTEXT=131072 IMG=tensorfold-qwen38:$IMGTAG bash ./patcheval.sh \
  "k1warm:" "k1base:" \
  "k1ahead0:TF_FLASHNEXT_DRAFT_AHEAD=0" \
  "k1early0:TF_FLASHNEXT_GATHER_EARLY=0" \
  "k1read0:TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_DRAFT_AHEAD=0" \
  "k1ngoff:$NGOFF" \
  "k1base2:" \
  "k1ngoffb:$NGOFF" \
  "k1base3:" > knobs21.log 2>&1
KV_DTYPE=fp8 CONTEXT=131072 IMG=tensorfold-qwen38:$IMGTAG bash ./patcheval.sh "k1fp8:" "k1fp8ngoff:$NGOFF" >> knobs21.log 2>&1
KV_DTYPE=fp8 CONTEXT=262144 IMG=tensorfold-qwen38:$IMGTAG bash ./patcheval.sh "k1fp8w:" >> knobs21.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch KNOBS21-DONE
