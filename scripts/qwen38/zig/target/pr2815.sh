#!/usr/bin/env bash
# pr2815.sh - upstream PR #2815 (two graphs a window-graph cache slot) on the repaired accepted rung: gp21 is g21
# plus the PR's one commit. A/B against g21 at one and four streams with the graphs on (the default), golden and
# self-check, and the engine's own "graphs: N captured, N updated, N replayed" lines from both.
# Runs behind halfk.sh, holding stage 3c's decode arms with HOLD2.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f MXK-DONE ] && break; sleep 20; done
touch HOLD2
for i in $(seq 1 900); do [ -f HALFK-DONE ] && break; sleep 20; done
bash ./build_rung.sh gp21 rungs/gp21.patch > pr2815.build.log 2>&1
export HOLD_FILE=none NORESTORE=1 KV_DTYPE=bf16 CONTEXT=131072
: > pr2815.log
run() { IMG="tensorfold-qwen38:$2" bash ./patcheval.sh "$1:" >> pr2815.log 2>&1; }
run p1warm g21
run p1base g21
run p1pr gp21
run p1base2 g21
run p1pr2 gp21
: > pr2815.graphs.log
for a in p1base p1pr p1base2 p1pr2; do for c in c1 c4; do
  printf '%s %s: %s\n' "$a" "$c" "$(grep -a 'graphs: ' "bench/pe-$a/$c/logs.txt" | tail -3 | sed 's/.*cuda_window_graph\.//' | cut -c1-90 | tr '\n' '|')" >> pr2815.graphs.log
done; done
rm -f HOLD2
touch PR2815-DONE
