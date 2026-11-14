#!/usr/bin/env bash
# fp4stack.sh [OUT] - the FP4 stack against production in one GPU window on spark6, through the int4win.sh beside it:
# production at 1, 2, 4, 6 and 8 streams (p), then for each stream count the defaults (d), the full stack (s), the
# stack again (s2) and the defaults again (d2), then production again (p2) for drift. NVFP4 checkpoint, image
# $IMG (default rq18), fp8 KV at 262,144, TF_FLASHNEXT_KV_PAGES=4096 at 6 and 8 streams in both arms, golden at one
# stream, one fresh boot a cell. STACK overrides the stack's switches. Summary: fp4stack.py LOG OUT.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$HOME/work/fp4stack/bench}
pages="TF_FLASHNEXT_KV_PAGES=4096"
stack=${STACK:-"TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8"}
cells=()
for c in 1 2 4 6 8; do cells+=("prod:p:$c"); done
for c in 1 2 4 6 8; do
  kv=""
  [ "$c" -ge 6 ] && kv=$pages
  cells+=("ours:d:$c:$kv" "ours:s:$c:$kv $stack" "ours:s2:$c:$kv $stack" "ours:d2:$c:$kv")
done
for c in 1 2 4 6 8; do cells+=("prod:p2:$c"); done
echo "=== fp4stack $(date -Is) image ${IMG:-tensorfold-qwen38:rq18} stack: $stack"
GOLD=1 CKPT=nvfp4 IMG=${IMG:-tensorfold-qwen38:rq18} OUT=$out bash "$here/int4win.sh" "${cells[@]}"
