#!/usr/bin/env bash
# fp4conf.sh [OUT] [dry] - the recommended FP4 launcher block, confirmed with two runs an arm: at each of 1, 2, 4, 6
# and 8 streams the defaults (d), the stack without TF_FLASHNEXT_HC_Q12=1 (n) and the full stack (s) in palindrome
# order d n s s2 n2 d2, one GPU window on spark6 through the int4win.sh beside it ("dry" lists the cells and exits).
# Settings as fp4stack.sh: image $IMG (default rq18), NVFP4, fp8 KV at 262,144, TF_FLASHNEXT_KV_PAGES=4096 at 6 and 8
# streams in every arm, golden at one stream, one fresh boot a cell. fp4stack.py then applies the noise rule (an arm is
# slower in a cell only when both its runs are under both runs of the other arm and the mean gap is over 1%) to n
# against d, s against d and n against s both ways, and writes OUT/rerun.txt ("streams arm..."); a second window reruns
# each listed stream count's arms in the same palindrome order (d3 n3 s3 s4 n4 d4, the listed arms only), and a cell
# slower again there is a loss. Log OUT.log; summary OUT/summary.txt (fp4stack.py OUT.log OUT).
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$HOME/work/fp4stack/conf}
log=$out.log
stack="TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8"
declare -A arm=([d]="" [n]="${stack/ TF_FLASHNEXT_HC_Q12=1/}" [s]="$stack")
cells() { # streams first-suffix second-suffix arm... : the arms forward with the first suffix, then backward
  local c=$1 one=$2 two=$3 kv="" a i
  shift 3
  [ "$c" -ge 6 ] && kv="TF_FLASHNEXT_KV_PAGES=4096"
  for a in "$@"; do echo "ours:$a$one:$c:$kv ${arm[$a]}"; done
  for ((i = $#; i > 0; i--)); do a=${!i}; echo "ours:$a$two:$c:$kv ${arm[$a]}"; done
}
mapfile -t first < <(for c in 1 2 4 6 8; do cells "$c" "" 2 d n s; done)
if [ "${2:-}" = dry ]; then
  printf '%s\n' "${first[@]}"
  exit 0
fi
win() {
  GOLD=1 CKPT=nvfp4 IMG=${IMG:-tensorfold-qwen38:rq18} OUT=$out bash "$here/int4win.sh" "$@" >> "$log" 2>&1
}
mkdir -p "$out"
echo "=== fp4conf $(date -Is) image ${IMG:-tensorfold-qwen38:rq18} stack: $stack; without HC_Q12: ${arm[n]}" >> "$log"
win "${first[@]}"
python3 "$here/fp4stack.py" "$log" "$out" > "$out/summary1.txt" 2>&1
if [ -s "$out/rerun.txt" ]; then
  # shellcheck disable=SC2086
  mapfile -t again < <(while read -r c arms; do cells "$c" 3 4 $arms; done < "$out/rerun.txt")
  echo "=== fp4conf rerun $(date -Is): $(tr '\n' ';' < "$out/rerun.txt")" >> "$log"
  win "${again[@]}"
fi
python3 "$here/fp4stack.py" "$log" "$out" > "$out/summary.txt" 2>&1
touch "$out/CONF-DONE"
