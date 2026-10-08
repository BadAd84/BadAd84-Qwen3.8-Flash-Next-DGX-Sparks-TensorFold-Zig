#!/usr/bin/env bash
# zqueue.sh CYCLES ARMFILE   (spark6, ~/work, detached): run every arm of ARMFILE (lines "LABEL VAR=VALUE ...", "#"
# comments) one boot and one pass each, CYCLES times, the order alternating each cycle (forward, then reversed);
# rows accumulate per label (zab-LABEL.jsonl is appended across cycles). Log zqueue.log.
set -uo pipefail
CYCLES=$1; ARMS=$2
cd "$HOME/work" || exit 1
exec > zqueue.log 2>&1
mapfile -t LINES < <(grep -v '^\s*#' "$ARMS" | grep -v '^\s*$')
for c in $(seq "$CYCLES"); do
  if (( c % 2 )); then ORDER=("${LINES[@]}"); else ORDER=(); for ((i=${#LINES[@]}-1; i>=0; i--)); do ORDER+=("${LINES[i]}"); done; fi
  for line in "${ORDER[@]}"; do
    read -r label rest <<<"$line"
    echo "=== cycle $c arm $label $(date +%T)"
    # one pass, rows appended to the arm's file across cycles
    if [[ -f "zab-$label.jsonl" ]]; then mv "zab-$label.jsonl" "zab-$label.keep"; fi
    # shellcheck disable=SC2086
    ./zarm.sh "$label" 1 $rest
    sed -i "s/\"label\": \"$label-p1\"/\"label\": \"$label-p$c\"/" "zab-$label.jsonl"
    if [[ -f "zab-$label.keep" ]]; then cat "zab-$label.jsonl" >> "zab-$label.keep"; mv "zab-$label.keep" "zab-$label.jsonl"; fi
    cp "zgold-$label.json" "zgold-$label-c$c.json"
    cat "zab-$label.log" >> "zab-$label.all.log"
    grep -a "=== pass\|^window 1 rows" "zab-$label.log"
  done
done
echo "=== ZQUEUE DONE $(date -Is)"
