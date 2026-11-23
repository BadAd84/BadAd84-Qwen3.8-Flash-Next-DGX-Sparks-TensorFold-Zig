#!/usr/bin/env bash
# starter.sh - wait for EnvBoot's fast r5 prompt-following verdict WITHOUT holding the GPU lock, then start the
# KnobScreen window under flock. Absence is not CLEAN: no lock is taken, no serve is touched, until the marker's
# first line reads CLEAN. A DEFECT line writes the numbers to out/GATE-STOP and exits without screening.
set -u
BOX=${KS_BOX:-$HOME/work/KnobScreen}
OUT=$BOX/out
LOG=$OUT/starter.log
EF=$HOME/work/EnvBoot/FAST-VERDICT
DEADLINE=$(( $(date +%s) + 12 * 3600 ))
mkdir -p "$OUT"
log() { echo "$(date -Is) $*" >> "$LOG"; }
GO=$BOX/GO
echo $$ > "$OUT/starter.pid"
log "START waiting for $EF (first line CLEAN) and $GO, holding no lock; deadline in 12 h"
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -s "$EF" ]; then
    first=$(head -1 "$EF" | tr -d '\r')
    if printf '%s' "$first" | grep -qiE '^(verdict:[[:space:]]*)?clean\b'; then
      if [ -f "$GO" ]; then
        cp "$EF" "$OUT/gate-marker.txt" 2>/dev/null || true
        log "GATES PASS first line [$first] and GO present: starting the window under flock now"
        KS_BOX="$BOX" KS_OUT="$OUT" bash "$BOX/driver.sh" run
        log "window returned $?"
        exit 0
      fi
      [ -f "$OUT/starter-clean-nogo" ] || { log "MARKER CLEAN but GO absent: waiting, taking no lock"; : > "$OUT/starter-clean-nogo"; }
    else
      echo "GATE-BLOCKED $first" > "$OUT/GATE-STOP"
      log "MARKER NOT CLEAN [$first]: no screening; wrote GATE-STOP"
      exit 8
    fi
  fi
  sleep 120
done
log "TIMEOUT: no marker in 12 h; no screening"
echo GATE-TIMEOUT > "$OUT/GATE-STOP"
exit 7
