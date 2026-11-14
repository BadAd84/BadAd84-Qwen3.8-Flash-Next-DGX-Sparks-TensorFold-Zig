#!/usr/bin/env bash
# fp4drop.sh [OUT] [dry] - the FP4 stack with one switch dropped at a time, one GPU window on spark6 through the
# int4win.sh beside it ("dry" lists the cells and exits). For each stream count (6 and 8 first): the defaults (d),
# the stack (s), the stack without the drafter's MXFP8 linears (m), the 12-bit read-outs (q), the fused split (f),
# the read-out fusion (r), SHARED_DRAFTS=0 (x, from two streams) and GREEDY_WIDE=8 (w, from six), the draft setting
# alone (t, from six), then the stack again (s2).
# Settings as fp4stack.sh. Summary: fp4stack.py LOG OUT.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$HOME/work/fp4stack/drop}
declare -A sw=([m]=TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 [q]=TF_FLASHNEXT_HC_Q12=1 [f]=TF_FLASHNEXT_FUSED_SPLIT=1
  [r]=TF_FLASHNEXT_READOUT_FUSE=1 [x]=TF_FLASHNEXT_SHARED_DRAFTS=0 [w]=TF_FLASHNEXT_GREEDY_WIDE=8)
all="${sw[m]} ${sw[q]} ${sw[f]} ${sw[r]} ${sw[x]} ${sw[w]}"
drop() {
  local s=" $all "
  echo "${s/ ${sw[$1]} / }"
}
cells=()
for c in 6 8 1 2 4; do
  kv=""
  arms="m q f r"
  [ "$c" -ge 2 ] && arms="$arms x"
  [ "$c" -ge 6 ] && arms="$arms w" && kv="TF_FLASHNEXT_KV_PAGES=4096"
  cells+=("ours:d:$c:$kv" "ours:s:$c:$kv $all")
  for a in $arms; do cells+=("ours:$a:$c:$kv $(drop "$a")"); done
  [ "$c" -ge 6 ] && cells+=("ours:t:$c:$kv ${sw[x]} ${sw[w]}")
  cells+=("ours:s2:$c:$kv $all")
done
echo "=== fp4drop $(date -Is) image ${IMG:-tensorfold-qwen38:rq18} stack: $all"
if [ "${2:-}" = dry ]; then
  printf '%s\n' "${cells[@]}"
  exit 0
fi
GOLD=1 CKPT=nvfp4 IMG=${IMG:-tensorfold-qwen38:rq18} OUT=$out bash "$here/int4win.sh" "${cells[@]}"
