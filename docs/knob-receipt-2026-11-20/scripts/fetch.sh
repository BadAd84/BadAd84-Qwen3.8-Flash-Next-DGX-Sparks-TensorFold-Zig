#!/usr/bin/env bash
# fetch.sh - copy the box's knob evidence into this repo's work/KnobTest/box (run from the laptop, top-level shell).
# The tree is tarred on the box first so one scp carries it; run logs, per-arm JSONs and the analysis come along.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BOXHOST=${BOXHOST:-adam@192.168.99.16}
ssh -o BatchMode=yes "$BOXHOST" 'cd ~/work/KnobTest && tar --exclude=MAIN --exclude=in -czf /tmp/knobtest-evidence.tgz out plans prod-env.txt scripts HANDOFF.md && sha256sum /tmp/knobtest-evidence.tgz && ls -la /tmp/knobtest-evidence.tgz' < /dev/null
mkdir -p "$HERE/box"
scp -o BatchMode=yes "$BOXHOST:/tmp/knobtest-evidence.tgz" "$HERE/box/"
cd "$HERE/box" && sha256sum -c <(ssh -o BatchMode=yes "$BOXHOST" 'cd /tmp && sha256sum knobtest-evidence.tgz' < /dev/null) && tar -xzf knobtest-evidence.tgz && echo "FETCHED $(date -Is)"
# the parsed analysis, one directory a window, under receipt/
rm -rf "$HERE/receipt" && mkdir -p "$HERE/receipt"
for w in "$HERE"/box/out/w*; do
  [ -d "$w/analysis" ] || continue
  name=$(basename "$w")
  cp -r "$w/analysis" "$HERE/receipt/$name"
done
ls -R "$HERE/receipt" 2>/dev/null | head -20
