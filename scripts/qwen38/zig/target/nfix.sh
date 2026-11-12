#!/usr/bin/env bash
# nfix.sh - the n-gram lever with its fill path merged correctly (overlay.py, rung 13): the row cache in front of
# the base's reader choice, not instead of it. Builds g21 (the accepted rung with the repair) and glog21 (g21 with
# the round log), prints where a decode round goes, then prices the repair and the reader choices on one image:
# the row cache (the recipe's GATHER_READ=pread), the base's positional reader, the base's mapped reader.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f "${WAIT:-STAGE3B-DONE}" ] && break; sleep 30; done
{
  bash ./build_rung.sh g21 rungs/g21.patch
  bash ./build_rung.sh glog21 rungs/glog21.patch
} > nfix.build.log 2>&1
PLAIN="TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_DRAFT_AHEAD=0"
bash ./profile_round.sh glog21 rungs/glog21.patch "log:" "plain:$PLAIN" "headbf16:TF_FLASHNEXT_DRAFT_HEAD=bf16" "drafts0:TF_FLASHNEXT_DRAFTS=0" > nfix.profile.log 2>&1
STREAMS=4 bash ./profile_round.sh glog21 rungs/glog21.patch "log:" >> nfix.profile.log 2>&1
touch PROFILE-DONE
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > nfix.log
run() { # name image env
  local name=$1 img=$2; shift 2
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> nfix.log; return; }
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:$*" >> nfix.log 2>&1
}
run n1warm g21
run n1old r0021
run n1fix g21
run n1plain g21 "$PLAIN"
run n1mmap g21 "$PLAIN TF_FLASHNEXT_PLE_IO=mmap"
run n1oldb r0021
run n1fixb g21
run n1plainb g21 "$PLAIN"
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch NFIX-DONE
