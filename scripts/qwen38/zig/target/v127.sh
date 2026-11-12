#!/usr/bin/env bash
# v127.sh - the series re-seated on TensorFold v1.2.7 (93a2e93ec), in the owner's order: stock first, then the
# levers one rung at a time. Images: up127 (v1.2.7, no patch) and v<N> = v1.2.7 plus the first N patches of the
# re-seated series (rungs127/v<N>.patch, cut by mkprefix.sh with BASE and SERIES set). Arms at bf16, 131,072, C=1 and
# C=4 through patcheval.sh, cold 8k and 32k prompts through prefill_arm.sh; golden is compared with v1.2.6 stock's.
# up126 and g21 (v1.2.6 stock and its accepted rung) run in the same sitting, so the release's own delta is measured.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 2400); do [ -f "${WAIT:-KNOBS21-DONE}" ] && break; sleep 30; done
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
echo "=== v1.2.7 into the build's git source $(date -Is)"
git -C ~/work/lanes/up-pr/tf fetch -q https://github.com/ashhart/TensorFold.git refs/tags/v1.2.7:refs/tags/v1.2.7
[ "$(git -C ~/work/lanes/up-pr/tf rev-parse 'v1.2.7^{commit}')" = "$BASE127" ] || { echo "v1.2.7 is not $BASE127: stop"; touch V127-DONE; exit 1; }
echo "=== builds $(date -Is)"
if ! docker image inspect tensorfold-qwen38:up127 > /dev/null 2>&1; then
  bash ~/work/merge/build-br.sh up127 git://192.168.99.16/up-pr/tf "$BASE127" > build-up127.out 2>&1
  echo "build up127 rc=$? $(grep -ac BUILD_OK build-up127.out)"
fi
RUNGS=${RUNGS:-1 3 4 5 6 7 8 9 10 11 13}
for K in $RUNGS; do BASE=$BASE127 bash ./build_rung.sh "v$K" "rungs127/v$K.patch"; done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > v127.log
run() { # name image [env]
  local name=$1 img=$2; shift 2
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> v127.log; return; }
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:$*" >> v127.log 2>&1
  for C in 1 4; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1)" >> v127.log
  done
}
echo "=== decode and golden $(date -Is)"
run v7warm up127
run v7s126 up126
run v7s127 up127
run v7g21 g21
for K in $RUNGS; do run "v7r$K" "v$K"; done
run v7s127b up127
echo "=== cold prompt time $(date -Is)"
specs="warm:up127: s126:up126: s127:up127: g21:g21:"
for K in $RUNGS; do specs="$specs r$K:v$K:"; done
# shellcheck disable=SC2086
bash ./prefill_arm.sh $(for s in $specs; do echo "v7$s"; done) "v7s127b:up127:" > v127.pf.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch V127-DONE
