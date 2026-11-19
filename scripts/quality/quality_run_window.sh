#!/usr/bin/env bash
# quality_run_window.sh - the A (INT4-AutoRound) against B (FP4-Local) quality window on spark6.
#
# Run INSIDE the GPU lock, detached, from the laptop:
#   ssh adam@192.168.99.16 'setsid nohup flock -o -w 43200 /home/adam/work/gpu.lock \
#       bash /home/adam/work/qualitycmp/run_window.sh > /home/adam/work/qualitycmp/out/nohup.log 2>&1 < /dev/null &'
#
# Inside the lock it: stops any orphaned container, starts production (~/qwen6-start-prod.sh, checkpoint
# A), captures its provenance, runs the three benchmarks (20-item dry run first, then all items), stops it,
# boots B from our recipe image on the NVIDIA FP4 checkpoint (candidate images tried in order), runs the
# identical benchmarks, then restores production and records /health. Every step is timestamped in
# out/driver.log; nothing is scored here.
set -uo pipefail
B=$HOME/work/qualitycmp
OUT=$B/out
URL=http://127.0.0.1:8888
CN=qwen38-flash-next-tf
RECIPE=$HOME/work/lanes/rpr/recipe
PRODSTART=$HOME/qwen6-start-prod.sh
PY=$(command -v python3)
CONC=4
DROP=0
NO_STOP=0
RESTORED=0
B_IMAGE=""
B_KV=""
MODEL=""
mkdir -p "$OUT" "$OUT/raw/A" "$OUT/raw/B"
LOG=$OUT/driver.log
exec >>"$LOG" 2>&1
say() { echo "[$(date -Is)] $*"; }
health() { local h; h=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "$URL/health" 2>/dev/null) || h=000; echo "${h:-000}"; }
model_id() { curl -s --max-time 10 "$URL/v1/models" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null; }
stop_container() { ( cd "$RECIPE" && ./stop.sh ) >/dev/null 2>&1; sleep 3; }
wait_health() { # seconds
  local i
  for i in $(seq 1 $(($1 / 10))); do [ "$(health)" = 200 ] && return 0; sleep 10; done
  return 1
}
capture() { # dir label
  local d=$1 label=$2
  mkdir -p "$d"
  {
    echo "arm=$label date=$(date -Is)"
    echo "docker_ps:"; docker ps --format '{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}'
    echo "models:"; curl -s --max-time 10 "$URL/v1/models"
    echo; echo "health:"; curl -s --max-time 10 "$URL/health"; echo
    echo "free_gib:"; awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
    echo "recipe_rev:"; ( cd "$RECIPE" && git rev-parse HEAD 2>/dev/null || echo "not-a-git-tree" )
    echo "python: $("$PY" -V 2>&1)"
    echo "client_sha256: $(sha256sum "$B/quality_client.py" | cut -d" " -f1)"
    echo "probe_sha256: $(sha256sum "$B/quality_probe_thinking.py" | cut -d" " -f1)"
    echo "prompts_sha256:"
    ( cd "$B/prompts" && sha256sum *.jsonl )
    echo "checkpoint_shapes:"
    for repo in azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound nvidia--Qwen3.8-Flash-Next-FP4-Local; do
      "$PY" -c 'import glob,json,sys
p=glob.glob(sys.argv[1]+"/snapshots/*/config.json")
c=json.load(open(p[0])) if p else {}
t=c.get("text_config",c)
print(sys.argv[1].split("models--")[-1].split("/")[0], {k:t.get(k) for k in ("num_experts_per_tok","shared_expert_intermediate_size","hidden_size","num_hidden_layers","quantization_config")})' "$HOME/.cache/huggingface/hub/models--$repo" 2>&1 | cut -c1-400
    done
  } > "$d/provenance.txt" 2>&1
  local image tag
  tag=$(docker inspect -f '{{.Config.Image}}' "$CN" 2>/dev/null)
  echo "container_image=$tag" >> "$d/provenance.txt"
  docker image inspect -f 'image {{.RepoTags}} id={{.Id}} created={{.Created}} kernels={{index .Config.Labels "tf.kernels"}} patches={{index .Config.Labels "tf.patches"}} ai={{index .Config.Labels "ai-engine.src-sha256"}} kindling={{index .Config.Labels "ai-engine.kindling"}}' "$tag" >> "$d/provenance.txt" 2>&1
  docker logs "$CN" > "$d/server.log" 2>&1
  head -80 "$d/server.log" > "$d/header.txt" 2>&1
  model_id > "$d/model.txt" 2>/dev/null
  echo "served_model=$(cat "$d/model.txt" 2>/dev/null)" >> "$d/provenance.txt"
}

run_bench() { # arm bench [extra client args]
  local arm=$1 bench=$2; shift 2
  local extra=""
  [ "$DROP" = 1 ] && extra="--drop-seed"
  [ "$NO_STOP" = 1 ] && extra="$extra --no-stop"
  ( cd "$B" && "$PY" quality_client.py --base "$URL" --model "$MODEL" --arm "$arm" --bench "$bench" \
      --prompts "$B/prompts/prompts_$bench.jsonl" --out "$OUT/raw/$arm/$bench.jsonl" \
      --concurrency "$CONC" $extra "$@" )
  local rc=$?
  say "CLIENT $arm $bench rc $rc drop_seed=$DROP"
  if [ $rc -eq 3 ] && [ "$DROP" = 0 ]; then
    DROP=1
    say "SEED REJECTED by the serve: rerunning $arm $bench for both arms with --drop-seed"
    run_bench "$arm" "$bench" "$@"
    return $?
  fi
  return $rc
}

probe() { # dir
  "$PY" "$B/quality_probe_thinking.py" --base "$URL" --prompts "$B/prompts/prompts_gsm8k.jsonl" \
    --out "$1/thinking_probe.json" >>"$1/probe.log" 2>&1
  say "PROBE $1 rc $?"
}

restore() {
  [ "$RESTORED" = 1 ] && return
  RESTORED=1
  say "RESTORE start"
  stop_container
  ( env LOCK_HOLDER=0 timeout 2400 "$PRODSTART" </dev/null ) > "$OUT/restore.log" 2>&1
  say "RESTORE prod rc $?"
  wait_health 1200
  say "RESTORE health $(health) models $(model_id)"
  curl -s --max-time 10 "$URL/health" > "$OUT/final_health.txt" 2>&1
  docker ps --format '{{.Names}} | {{.Image}} | {{.Status}}' > "$OUT/final_docker_ps.txt" 2>&1
  curl -s --max-time 10 "$URL/v1/models" > "$OUT/final_models.json" 2>&1
  say "RESTORE done"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP

say "WINDOW start host=$(hostname) python=$("$PY" -V 2>&1)"
say "GPU lock holders before us: $(pgrep -af 'flock.*gpu.lock' | grep -v $$ | head -3 | tr '\n' ';')"
stop_container                      # inside the lock: anything still up is an orphan from a released lock
say "PRE clean container stopped"

# ---- arm A: production's own serve
mkdir -p "$OUT/A"
say "A boot start"
( env LOCK_HOLDER=0 timeout 2400 "$PRODSTART" </dev/null ) > "$OUT/A/boot.log" 2>&1
say "A boot rc $?"
if ! wait_health 1200; then
  say "A FAILED to answer /health: $(health)"; capture "$OUT/A" A; exit 1
fi
MODEL=$(model_id)
say "A live model=$MODEL health=$(health)"
capture "$OUT/A" A
probe "$OUT/A"
if ( cd "$B" && "$PY" quality_client.py --probe-stop --base "$URL" --model "$MODEL" --arm A --bench gsm8k \
        --prompts "$B/prompts/prompts_gsm8k.jsonl" ); then
  say "STOP FIELD accepted by A: benchmarks keep their stop sequences"
else
  NO_STOP=1
  say "STOP FIELD rejected by A: both arms run WITHOUT stop (recorded)"
fi

say "A dry run 20 each"
for bench in gsm8k mmlupro humaneval; do run_bench A "$bench" --limit 20; done
say "A dry run done"
say "A full run"
for bench in gsm8k mmlupro humaneval; do run_bench A "$bench"; done
say "A full run done lines $(wc -l < "$OUT/raw/A/gsm8k.jsonl") $(wc -l < "$OUT/raw/A/mmlupro.jsonl") $(wc -l < "$OUT/raw/A/humaneval.jsonl")"
stop_container
say "A stopped"

# ---- arm B: our recipe image on nvidia/Qwen3.8-Flash-Next-FP4-Local
boot_b() {
  local img kv d rc
  for img in pvz-fp4 t5-b-c0eb2126 v18 wb n3218-mn; do
    docker image inspect "tensorfold-qwen38:$img" >/dev/null 2>&1 || { say "B candidate $img absent"; continue; }
    for kv in fp8 bf16; do
      d=$OUT/B-try-$img-$kv
      mkdir -p "$d"
      say "B boot try image=$img kv=$kv"
      ( cd "$RECIPE" && timeout 2400 env PREPARE=0 IMAGE="tensorfold-qwen38:$img" VISION=0 \
          TENSORFOLD_CUDA_KERNELS=native KV_DTYPE="$kv" PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8888 \
          MEM_CHECK=0 THINKING=0 DRAFTS=1 CHECKPOINT=nvfp4 ./start.sh restart ) > "$d/boot.log" 2>&1
      rc=$?
      docker logs "$CN" > "$d/server.log" 2>&1
      say "B boot rc $rc image=$img kv=$kv health=$(health)"
      if [ $rc -eq 0 ] && [ "$(health)" = 200 ] && grep -qa "nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6" "$d/boot.log"; then
        B_IMAGE=$img; B_KV=$kv
        say "B boot OK image=$img kv=$kv model=$(model_id)"
        cp "$d/boot.log" "$OUT/B-boot.log"; mv "$d" "$OUT/B"
        return 0
      fi
      stop_container
    done
  done
  return 1
}
if ! boot_b; then
  say "B FAILED: no candidate image booted the FP4 checkpoint"
  exit 1
fi
MODEL=$(model_id)
say "B live image=$B_IMAGE kv=$B_KV model=$MODEL health=$(health)"
capture "$OUT/B" "B image=$B_IMAGE kv=$B_KV"
probe "$OUT/B"
if ( cd "$B" && "$PY" quality_client.py --probe-stop --base "$URL" --model "$MODEL" --arm B --bench gsm8k \
        --prompts "$B/prompts/prompts_gsm8k.jsonl" ); then
  say "STOP FIELD accepted by B (NO_STOP=$NO_STOP)"
else
  say "STOP FIELD REJECTED by B: proceedings differ from A; flagged for the report"
fi

say "B dry run 20 each"
for bench in gsm8k mmlupro humaneval; do run_bench B "$bench" --limit 20; done
say "B dry run done"
say "B full run"
for bench in gsm8k mmlupro humaneval; do run_bench B "$bench"; done
say "B full run done lines $(wc -l < "$OUT/raw/B/gsm8k.jsonl") $(wc -l < "$OUT/raw/B/mmlupro.jsonl") $(wc -l < "$OUT/raw/B/humaneval.jsonl")"
stop_container
say "B stopped"

say "WINDOW benchmarks done"
exit 0
