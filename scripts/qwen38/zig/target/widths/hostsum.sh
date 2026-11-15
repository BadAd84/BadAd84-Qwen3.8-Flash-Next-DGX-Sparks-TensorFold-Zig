#!/usr/bin/env bash
# hostsum.sh [GLOB] - failing, crashed and timed-out tests in the WSL host-step logs, with the lines that follow each.
W=/home/adam/work/tensorfold/widths
for f in "$W"/${1:-steps-*.log}; do
  echo "== ${f##*/}"
  tr '\r' '\n' < "$f" | grep -a -E -A4 "error: '.*' (failed|terminated)|timed out|timeout" | grep -v "patch_embed" | head -30 | cut -c1-230
done
