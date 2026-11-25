#!/usr/bin/env bash
# sd-collect.sh - insurance on spark6: when the window writes WINDOW-DONE, tar the evidence bundle, generate
# RESULT.md from the stored evidence, and write a one-screen collect.log; if the window process disappears
# without the marker, record its tail.
set -u
BOX=$HOME/work/SharedDraftsMain
OUT=$BOX/out
LOG=$OUT/collect.log
REPORT=$BOX/RESULT.md
mkdir -p "$OUT"
for i in $(seq 1 720); do
  if grep -q "WINDOW-DONE" "$OUT/run.log" 2>/dev/null; then
    sleep 30
    tar -czf "$BOX/out-bundle.tgz" -C "$BOX" out
    python3 "$BOX/in/sd_report.py" --root "$OUT" --build-receipt "$BOX/BUILD-RECEIPT.md" --out "$REPORT" \
      > "$OUT/report.log" 2>&1 || true
    {
      echo "COLLECT $(date -Is)"
      echo "bundle_bytes $(stat -c %s "$BOX/out-bundle.tgz" 2>/dev/null)"
      echo "report $(tail -1 "$OUT/report.log" 2>/dev/null)"
      echo "score $(grep -m1 '^SCORE-SUMMARY' "$OUT"/score*.txt 2>/dev/null | tail -1)"
      grep -E "^(RESTORED|WINDOW-DONE|IDENTITY-WRONG|SMOKE-FAILED|ABORT)" "$OUT/run.log" | tail -8
    } > "$LOG" 2>&1
    exit 0
  fi
  if ! pgrep -f "[s]d-window.sh" >/dev/null; then
    { echo "COLLECT window process gone without WINDOW-DONE $(date -Is)"; tail -20 "$OUT/run.log" 2>/dev/null; } > "$LOG" 2>&1
    exit 1
  fi
  sleep 60
done
echo "COLLECT timeout $(date -Is)" > "$LOG"
exit 1
