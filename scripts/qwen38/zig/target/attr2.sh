#!/usr/bin/env bash
# attr2.sh - attribute production's decode lead with production's OWN launcher (its binary predates --kv-cache, so
# the 1.2.6 recipe cannot boot it). Each arm: stop, boot with one lever switched off, one decode pass at one
# stream on the code prompt, then restore.
set -u
cd ~/work/target || exit 1
cp ~/qwen6-start-prod.sh prod-arm.sh
sed -i 's|^  ./start.sh restart$|  ${EXTRA:-} ./start.sh restart|' prod-arm.sh
grep -n "EXTRA" prod-arm.sh | head -2
mkdir -p bench
run() {
  local name=$1 extra=$2
  ( ~/qwen-zig-prod/stop.sh ) > /dev/null 2>&1
  docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
  echo "=== $name extra: ${extra:-none} $(date -Is)"
  ( env EXTRA="$extra" LOCK_HOLDER=0 bash ./prod-arm.sh </dev/null ) > "bench/attr-$name.boot.log" 2>&1
  local t=0; while [ $t -lt 240 ]; do curl -sf -m 3 -o /dev/null http://127.0.0.1:8888/health && break; sleep 5; t=$((t+5)); done
  echo "ready after ${t}s"
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "attr-$name" 1 "$HOME/work/target/bench/attr-$name.dec.jsonl" 1 \
    2>&1 | grep -a "^DEC" | head -2 | cut -c1-110
}
for pair in "base:" "nomtpq4:TF_FLASHNEXT_MTP_Q4=0" "nodraftint4:TF_FLASHNEXT_DRAFT_INT4=0" "noup:TF_FLASHNEXT_UPMIX_DECODE=0" "noqsa:TF_FLASHNEXT_QSA_SELECT=0" "noearly:TF_FLASHNEXT_EARLY_DRAW=0" "nomtpfp8:TF_FLASHNEXT_MTP_FP8="; do
  run "${pair%%:*}" "${pair##*:}"
done
( ~/qwen-zig-prod/stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== production $(date -Is)"
touch "$HOME/work/target/ATTR2-DONE"
