#!/usr/bin/env bash
# mverify10.sh (under the GPU lock): W7's two settings on zmerge5. (1) TF_FLASHNEXT_PREFILL_ROWS=4096 vs default 2048:
# cold prefill of new text at 32k and 128k, alternating boots. (2) TF_FLASHNEXT_FILL=1 vs 0: golden + decode matrix
# (exactness on the merged engine) and a stall test (one client decoding while another sends a 32k prompt).
set -uo pipefail
cd ~/work/merge/v || exit 1
cat > pf3.py <<'EOF'
import json, statistics, sys
import qf_harness as H
arm, out, base = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(out, "a") as f:
    for n in (32000, 128000):
        rates = []
        for run in range(2):
            r = H.complete(H.prose(n, base + n + run * 7919), 16)
            rates.append(r["prompt_tokens"] / r["ttft"])
            f.write(json.dumps({"arm": arm, "n": n, "run": run, "ttft": r["ttft"], "rate": rates[-1]}) + "\n")
        print(f"{arm} prefill {n}: {statistics.median(rates):.0f} tok/s {[round(x) for x in rates]}", flush=True)
EOF
cat > stall.py <<'EOF'
import json, sys, threading, time, urllib.request
import qf_harness as H
arm = sys.argv[1]
gaps = []
def decoder():
    body = H.body_of(H.PROSE_PROMPTS[0] + f" (stall {time.time()})", 1024)
    req = urllib.request.Request(H.API + "/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    last = None
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            if line.startswith(b"data: ") and b"content" in line:
                now = time.time()
                if last is not None: gaps.append(now - last)
                last = now
t = threading.Thread(target=decoder); t.start(); time.sleep(3)
t0 = time.time(); r = H.complete(H.prose(32000, int(time.time()) % 100000 + 777000), 16); ttft = r["ttft"]
t.join()
print(f"{arm} stall: decoding client's longest gap {max(gaps):.2f} s, 32k prompt TTFT {ttft:.2f} s")
EOF
COMMON="PREPARE=0 IMAGE=tensorfold-qwen38:zmerge5 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_COPY_SHARED=1"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "prompt path\|fill" | head -2
  [[ "${WARM:-0}" == 1 ]] && return
  python3 pf3.py "$l" "zp10-$l.jsonl" "$(( 800000 + RANDOM * 64 ))"
  python3 stall.py "$l"
}
WARM=1 arm v10warm $COMMON
arm v10r2a $COMMON
arm v10r4a $COMMON TF_FLASHNEXT_PREFILL_ROWS=4096
arm v10fla $COMMON TF_FLASHNEXT_FILL=1
arm v10flb $COMMON TF_FLASHNEXT_FILL=1
arm v10r4b $COMMON TF_FLASHNEXT_PREFILL_ROWS=4096
arm v10r2b $COMMON
echo "##### done $(date -Is)"
