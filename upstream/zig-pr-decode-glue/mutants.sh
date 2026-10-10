#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0019's byte check. `tensorfold glue-check` runs the reduce-act check
# (tf_fn_hc_reduce_act_kernel against _reduce + _hc_act, 134 cases) and the up-mix check at 2-16 rows; it prints PASS
# or FAIL for each. Its last part (wbNormCheck) stops on the stock kernel set at a variant it lacks, so the command's
# exit code is not the verdict: read the "reduce-act-check" line and the "hc_reduce_act" / up-mix lines. Lane w5-opus
# (~/work/lanes/w5-opus/glue-check-final.log): EQUAL on 134 cases; the slice-order mutant (glue-check-ramut.log)
# 44 DIFFER = killed; the up-mix's last-row mutant golden 3/6 = killed. Re-run on the clean stack's image:
set -uo pipefail
IMG=${1:-tensorfold-qwen38:zpr-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
out=$(flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold glue-check "$SNAP" 2>&1)
echo "$out" | grep -a "reduce-act-check\|hc_reduce_act\|DIFFER"
echo "$out" | grep -aq "^PASS reduce-act-check" && ! echo "$out" | grep -aq "DIFFER"
