#!/usr/bin/env bash
# locknest_test.sh - proves run_knobs.sh's lock handoff cannot self-deadlock, with a stub lock in a temp dir.
# The shape under test is the driver's own: one marker variable (KL_LOCKED) set by the flock wrapper, tested by the
# re-executed child, with the window argument carried through.
set -u
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
L=$T/gpu.lock
: > "$L"
cat > "$T/driver.sh" <<'INNER'
WINDOW=${1:?window}
if [ "${KL_LOCKED:-}" != 1 ]; then
  flock -o -w 10 "$LOCK" env KL_LOCKED=1 bash "$0" "$WINDOW"
  echo "driver: outer exit $?"
  exit
fi
echo "driver: ran window $WINDOW under KL_LOCKED=$KL_LOCKED"
INNER
echo "== one acquisition, no other holder"
t0=$(date +%s)
LOCK="$L" bash "$T/driver.sh" w1
echo "elapsed $(( $(date +%s) - t0 ))s (a few seconds means one acquisition)"
echo "== a foreign holder first (another lane), the driver must queue then run"
( flock -w 10 9; sleep 3; echo "fd-holder: released at $(date +%s)" ) 9>"$L" &
h=$!
sleep 1
t0=$(date +%s)
LOCK="$L" bash "$T/driver.sh" w2
echo "elapsed $(( $(date +%s) - t0 ))s (blocked while the holder ran, then acquired)"
wait $h
echo "== the historical failure: parent holds KL_LOCKED, child tests another name"
cat > "$T/old.sh" <<'INNER'
if [ "${OTHER_LOCKED:-}" = 1 ]; then echo "old: ran"; exit 0; fi
flock -o -w 5 "$LOCK" env OTHER_LOCKED=1 bash "$0"
echo "old: flock returned $? after waiting for its own parent"
INNER
t0=$(date +%s)
flock -o -w 10 "$L" env KL_LOCKED=1 LOCK="$L" bash "$T/old.sh"
echo "old shape elapsed $(( $(date +%s) - t0 ))s (5 s is the child waiting on its own parent)"
