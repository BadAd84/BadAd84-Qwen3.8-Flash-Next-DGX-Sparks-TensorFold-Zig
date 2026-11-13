#!/usr/bin/env bash
# receipt0014.sh - the receipt of the TF_FLASHNEXT_MTP_WEIGHTS pull request: upstream main alone (arm `main`), the PR
# branch with the setting unset (`pr-default`, must equal main) and with mxfp8 (`pr-mxfp8`), main again at the end.
# Upstream's own clients (tools/bench_openai.py, tools/bench_concurrent.py --alone --serial) at 1, 2 and 4 streams,
# greedy, 256 tokens, 3 reps, and our golden for the reply hashes and the cold 8k and 32k prompts. NVFP4 checkpoint,
# bf16 KV, 131,072 window, one fresh boot an arm, GPU lock held for the whole run, production restored at the end.
# Needs ~/work/target/up-tools (upstream tools/ at the PR's base) and rungs127/pr0014.patch (the PR commit's diff).
set -u
cd ~/work/target || exit 1
exec 9>~/work/gpu.lock
flock -w 21600 9 || { echo "receipt0014: the GPU lock is held"; exit 1; }
OUT=bench/pr0014; mkdir -p "$OUT"; : > receipt0014.log
BASEM=$(cat up-tools/BASE_SHA)
git -C ~/work/lanes/up-pr/tf fetch -q https://github.com/ashhart/TensorFold.git "$BASEM" 2>/dev/null || git -C ~/work/lanes/up-pr/tf fetch -q https://github.com/ashhart/TensorFold.git main
git -C ~/work/lanes/up-pr/tf cat-file -e "$BASEM^{commit}" || { echo "base $BASEM not fetched" >> receipt0014.log; exit 1; }
git -C ~/work/lanes/up-pr/tf update-ref refs/heads/um-main "$BASEM"
docker image inspect tensorfold-qwen38:um > /dev/null 2>&1 || bash ~/work/merge/build-br.sh um git://192.168.99.16/up-pr/tf "$BASEM" > build-um.out 2>&1
BASE=$BASEM bash ./build_rung.sh um14 rungs127/pr0014.patch >> receipt0014.log 2>&1
for im in um um14; do docker image inspect tensorfold-qwen38:$im > /dev/null 2>&1 || { echo "image $im missing" >> receipt0014.log; exit 1; }; done
arm() { # name image [env...]
  local name=$1 img=$2; shift 2
  local d="$OUT/$name"; mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
      KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  docker logs qwen38-flash-next-tf > "$d/server.log" 2>&1
  echo "=== $name $(date -Is) gpu $(nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' ')" >> receipt0014.log
  grep -a "MTP_WEIGHTS\|re-coded\|kept as\|self-check" "$d/server.log" | head -3 | cut -c1-160 >> receipt0014.log
  model=$(curl -s http://127.0.0.1:8080/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  ( cd up-tools/.. && python3 up-tools/bench_openai.py http://127.0.0.1:8080 "$model" --tokens 256 --reps 3 --temperatures 0 --label "$name" --output "$d/decode.json" ) >> "$d/decode.out" 2>&1
  python3 up-tools/bench_concurrent.py http://127.0.0.1:8080 "$model" --tokens 256 --reps 3 --temperatures 0 --levels 1,2,4 --alone --serial --output "$d/concurrent.json" >> "$d/concurrent.out" 2>&1
  ( cd ~/work && python3 qf_harness.py golden "$HOME/work/target/$d/zgold.json" | tail -1 ) >> receipt0014.log 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
arm main um
arm pr-default um14
arm pr-mxfp8 um14 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
arm main-again um
for n in pr-default pr-mxfp8 main-again; do
  echo "GOLD $n $(python3 ~/work/zgold_cmp.py $OUT/main/zgold.json $OUT/$n/zgold.json 2>&1 | tail -1 | grep -o '[0-9]/6 [a-z]*')" >> receipt0014.log
done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1 HOLD_FILE=none
bash ./prefill_arm.sh "pfmain:um:" "pfdefault:um14:" "pfmx:um14:TF_FLASHNEXT_MTP_WEIGHTS=mxfp8" "pfmain2:um:" >> receipt0014.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> receipt0014.log
touch RECEIPT0014-DONE
