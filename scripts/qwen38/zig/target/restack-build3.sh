#!/usr/bin/env bash
# build3.sh - wait for other docker builds, then build um96 (upstream main alone), rs96 (the re-seated series)
# and rq7 (the 1.2.7 series) on spark6.
set -uo pipefail
cd "$HOME/work/target" || exit 1
for i in $(seq 1 360); do
  if ! pgrep -f "docker build -t tensorfold-qwen38" >/dev/null; then break; fi
  sleep 20
done
echo "== um96: upstream main alone at 964174ea05"
( cd "$HOME/work/merge" && ./build-br.sh um96 git://192.168.99.16/up-pr/tf 964174ea05879e6dde1de1198a3aae3ef8b46a3b ) || echo "UM96-FAILED"
echo "== rs96: the re-seated series"
./build_patches.sh rs96 git://192.168.99.16/up-pr/tf 964174ea05879e6dde1de1198a3aae3ef8b46a3b "$HOME/work/target/rs96" || echo "RS96-FAILED"
echo "== rq7: the 1.2.7 series"
./build_patches.sh rq7 git://192.168.99.16/up-pr/tf 93a2e93ecebff8aa52b88e58c5dd222516e69c5f "$HOME/work/target/rq7" || echo "RQ7-FAILED"
echo ALLBUILDS-DONE
