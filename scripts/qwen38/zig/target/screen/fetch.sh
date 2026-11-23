#!/usr/bin/env bash
# fetch.sh - pull the KnobScreen window's receipts from spark6 without the per-boot server logs (kept on the box).
# Writes work/KnobScreen/fetched/ and prints the analyzer's table and scores. Git Bash, top level.
set -eu
H=${KS_HOST:-adam@192.168.99.16}
HERE=$(cd "$(dirname "$0")" && pwd)
export SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-C:/Users/Adam/AppData/Local/gnupg/agent-gui/S.gpg-agent.ssh.cyg}
rm -rf "$HERE/fetched"
mkdir -p "$HERE/fetched"
ssh -o BatchMode=yes -o ConnectTimeout=20 "$H" \
  "tar czf - -C \$HOME/work/KnobScreen out GATE production.txt 2>/dev/null" < /dev/null > "$HERE/fetched/out.tgz"
tar xzf "$HERE/fetched/out.tgz" -C "$HERE/fetched"
rm -f "$HERE/fetched/out.tgz"
echo "=== boot records ==="
find "$HERE/fetched/out" -name meta.json | wc -l
echo "=== table ==="
cat "$HERE/fetched/out/table.md" 2>/dev/null || echo "no table.md"
echo "=== scores ==="
cat "$HERE/fetched/out/scores.tsv" 2>/dev/null || echo "no scores.tsv"
echo "=== end state ==="
cat "$HERE/fetched/out/production.txt" 2>/dev/null || echo "no production.txt"
cat "$HERE/fetched/out/LEFT" 2>/dev/null || true
cat "$HERE/fetched/GATE" 2>/dev/null || true
