#!/usr/bin/env bash
# waitreceipt.sh [MAX_MIN] - on spark6: wait (up to MAX_MIN minutes, default 58) for the widths receipt and its
# exactness arms, then print them.
R=$HOME/work/widths/receipt
for _ in $(seq 1 $(( ${1:-58} * 2 ))); do
  [ -f "$R/exact/DONE" ] && break
  sleep 30
done
date -u
grep -a -E "^(START|BUILD|IMAGE|MLX|MEM|CHECK|RC|RESTORE|ARMS)" "$R/run.log" | cut -c1-230
for a in M1 B1 B2 M2; do
  echo "--- $a"
  grep -a -v "^\s*$" "$R/$a/conc_t0.out" 2>/dev/null | tail -8 | cut -c1-200
  grep -a -v "^\s*$" "$R/$a/openai_t0.out" 2>/dev/null | tail -3 | cut -c1-200
  cat "$R/$a/metrics.txt" 2>/dev/null | cut -c1-230
done
cat "$R/exact/run.log" 2>/dev/null | cut -c1-160
cat "$R/exact/summary.md" 2>/dev/null | head -40 | cut -c1-200
