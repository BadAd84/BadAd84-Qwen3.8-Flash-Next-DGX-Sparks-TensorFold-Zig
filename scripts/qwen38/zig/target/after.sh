#!/usr/bin/env bash
# after.sh - waits for the target matrix to finish, then builds the stock upstream v1.2.6 image as up126.
# Runs detached beside target_queue.sh so the build never shares the box with a timed cell.
set -u
cd "$HOME/work/target" || exit 1
while [ ! -f DONE ]; do sleep 30; done
echo "=== target matrix done $(date -Is)"
git -C "$HOME/work/lanes/up-pr/tf" fetch -q https://github.com/ashhart/TensorFold.git "v1.2.6:refs/tags/v1.2.6" || true
echo "up-pr/tf tip before: $(git -C "$HOME/work/lanes/up-pr/tf" log --oneline -1)"
bash "$HOME/work/merge/build-br.sh" up126 git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 > build-up126.log 2>&1
echo "build up126 rc=$? $(docker image inspect tensorfold-qwen38:up126 --format '{{.Id}}' 2>/dev/null | cut -c8-19)"
grep -aE "^BUILT|error" build-up126.log | tail -5
