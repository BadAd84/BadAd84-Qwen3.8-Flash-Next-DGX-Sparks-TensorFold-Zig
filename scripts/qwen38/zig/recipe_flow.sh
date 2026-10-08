#!/usr/bin/env bash
# recipe_flow.sh DIR MTP_DIFF ARGMAX_PATCH   (spark6, detached): the upstream packages through the recipe's own flow.
# A fresh clone of the recipe's main in DIR, the MTP package's pr.diff applied and the argmax package's patch file
# copied in beside it, then scripts/prepare.sh (builds the image locally: no prebuilt matches the new patch hash,
# writes the MTP overlay as the user), start.sh with TF_FLASHNEXT_CONFIDENCE=-0.15 (the third package's default),
# then the recipe's checks against the server. Log DIR.log.
set -uo pipefail
DIR=$1; MTP=$(readlink -f "$2"); ARGMAX=$(readlink -f "$3")
exec > "$DIR.log" 2>&1
rm -rf "$DIR"
git clone -q -c core.autocrlf=false https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold.git "$DIR" || exit 1
cd "$DIR" || exit 1
git log --oneline -1
git apply "$MTP" || { echo "MTP diff does not apply"; exit 1; }
cp "$ARGMAX" patches/0010-flash-next-argmax-lse-rows.patch
ls patches
echo "=== prepare $(date -Is)"
IMAGE=tensorfold-qwen38:zig-pr-check PULL=0 ./scripts/prepare.sh </dev/null; echo "PREPARE EXIT $?"
ls -la "$HOME/.cache/huggingface/tensorfold-mtp-fp8/"*/* 2>&1 | tail -3
echo "=== start $(date -Is)"
IMAGE=tensorfold-qwen38:zig-pr-check TF_FLASHNEXT_CONFIDENCE=-0.15 ./start.sh restart </dev/null | grep -a "answered\|LIVE\|ERROR\|WARN\|OK:"; echo "START EXIT ${PIPESTATUS[0]}"
docker inspect qwen38-flash-next-tf --format '{{.Config.Image}} {{range .Config.Env}}{{if eq (slice . 0 9) "TF_FLASHN"}}{{.}} {{end}}{{end}}'
docker logs qwen38-flash-next-tf 2>&1 | grep -a "overlay\|startup estimate\|serving\|admit" | head
echo "=== checks $(date -Is)"
python3 tools/exact.py; echo "EXACT EXIT $?"
python3 tools/toolcheck.py; echo "TOOLCHECK EXIT $?"
python3 tools/needle.py; echo "NEEDLE EXIT $?"
echo "=== RECIPE FLOW DONE $(date -Is)"
