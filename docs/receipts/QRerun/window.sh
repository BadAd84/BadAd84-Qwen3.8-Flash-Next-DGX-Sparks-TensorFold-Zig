#!/usr/bin/env bash
# window.sh - one hold of ~/work/gpu.lock on spark6 for the QRerun window: r5 FP4 against r5 INT4 on the fixed
# build, the 20-item fidelity gate per arm, the 1,664 frozen bodies an arm, the checkpoint-only decode cells and the
# three exactness cells.
#
#   0  preflight: payload sums, patch package sums, production up and pinned, no foreign container, start.lock free,
#      disk, load. A held start.lock or a production container this window does not recognise stops it here.
#   1  stage both trees: the base tarball verified against in/ls-tree.z blob by blob and mode by mode, the 20 r5
#      patches (arm A) and then the 2 INT4 patches (arm B) applied in filename order, each tree verified blob by blob
#      against its manifest (A: in/fp4.manifest generated on the laptop from the same package; B: in/int4.manifest,
#      the independent lane's ab6389fc... record).
#   2  build both images from those trees (Dockerfile.arm, SOURCE line, tf.tree.manifest and tf.source labels,
#      relabel embedded), record image ids and labels.
#   3  arm A: boot the matched block, read the environment back and diff it, gate the boot banner on the arm's own
#      checkpoint identity, run the 20-item oracle against the FP4 reference (QCMPB) and stop if it is not 20 of 20,
#      then send the 500 + 1,000 + 164 frozen bodies at concurrency 4.
#   4  arm B: the same boot and banner, then the INTERNAL gate on its own arithmetic: the 20-item oracle drafted
#      against "draft": false on the same boot (token ids and the server's token sha equal, the drafter proven to
#      have run on the drafted pass and proven stopped on the plain one), where a differently configured INT4 serve
#      is never a reference; then the same 1,664 frozen bodies. X1 (resumed equals fresh) and X2 (drafted equals
#      plain on decoded cells) run for arm B in step 6 and fail the window if they fail.
#   5  speed: D1, D4 and D8, prose and code, two boots an arm a stream count, arms alternating; every boot a fresh
#      serve, every pass checked for all rows, rates and counters.
#   6  exactness: X1 resumed equals fresh on the 8,606-token prompt (both arms), X2 drafted equals plain at C=1 and
#      C=4, X3 shared rounds keep every reply sha at C=4.
#   7  verify the 1,664 bodies against the frozen prompt files and across arms; then restore production from the
#      EXIT trap, gated on /health 200 and the pinned image id.
#
# Modes:
#   window     the run above (takes ~/work/gpu.lock unless QR_LOCKED=1); idempotent: a step whose marker and data
#              both check out is skipped, so an interrupted window resumes with `window` again
#   preflight  the checks only, nothing stopped, nothing written but $OUT logs
#   selftest   stub every gate with a fixture and require each to open on a good fixture and stop on a bad one
#   restore    stop the serve and restore production
#
# Markers in $OUT/marks: LOCKED PREFLIGHT-OK STAGE-A-OK STAGE-B-OK BUILD-A-OK BUILD-B-OK BOOT-<label>-OK
#   FID-A-OK (external, QCMPB 20/20) FID-B-OK (internal, drafted equals draft:false 20/20) QUAL-A-OK QUAL-B-OK
#   SPEED-<label>-OK X1-<arm>-OK X2-<arm>-OK X3-<arm>-OK QVERIFY-OK
#   SELFTEST-OK RUN-DONE RESTORED PROD-IMAGE-OK RUN-STOP
set -u
SELF=$(readlink -f "$0")
BOX=${QR_BOX:-$HOME/work/QRerun}
IN=$BOX/in
OUT=${QR_OUT:-$BOX/out}
MARKS=$OUT/marks
TREES=$BOX/trees
RECIPE=${RECIPE:-$HOME/work/lanes/rpr/recipe}
PROD_START=${PROD_START:-$HOME/qwen6-start-prod.sh}
RELABEL=${RELABEL:-$HOME/work/lanes/fp4port/relabel.sh}
CN=qwen38-flash-next-tf
URL=${QR_URL:-http://127.0.0.1:8080}
PRODURL=http://127.0.0.1:8888
IMG_A=tensorfold-qwen38:qr-a-r5-1ece6e6db
IMG_B=tensorfold-qwen38:qr-b-r5int4-1ece6e6d
PROD_IMAGE=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
PROD_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
BASE_IMAGE=nvcr.io/nvidia/pytorch:26.07-py3
BASEIMG=tensorfold-qwen38:zig-db28187
ZIG_VERSION=0.17.0
ZIG_SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
BASE=1ece6e6dbbc073582d50738ce8e73e3c3261a73b
MODEL=Qwen3.8-Flash-Next
MODEL_A=nvidia/Qwen3.8-Flash-Next-FP4-Local
REV_A=b9ce18a6887e18c089fdea8509a33e63429a3300
SUB_A=models--nvidia--Qwen3.8-Flash-Next-FP4-Local
MODEL_B=azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound
REV_B=1464274120d36a4d8fcaa934552334a7d83ce0fd
SUB_B=models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound
BLOCK_ALL="TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0"
BLOCK_NOSD="TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15"
LOCKF=${LOCKF:-$HOME/work/gpu.lock}
START_LOCK=$HOME/.local/state/qwen38-flash-next-tf/start.lock
POLL=${QR_POLL:-2}
CONC=${QR_CONC:-4}
DISK_MIN=${QR_DISK_MIN:-60}
PASSES=${QR_PASSES:-2}
STOPPED_PROD=0
PREFLIGHT_PROD_DOWN=0
ROWS_WANT=${QR_ROWS:-3072}

mkdir -p "$OUT" "$MARKS" 2>/dev/null || true
if [ "${1:-}" = window ] && [ "${QR_LOCKED:-0}" != 1 ]; then
  mkdir -p "$OUT" "$MARKS"
  exec flock -o -w 43200 "$LOCKF" env QR_LOCKED=1 QR_BOX="$BOX" QR_OUT="$OUT" bash "$SELF" window "$BOX"
fi

log() { echo "["$(date -Is)"] $*" >> "$OUT/run.log"; }
now() { date -Is; }
mark() { : > "$MARKS/$1"; log "MARK $1"; }
memavail() { awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo; }
free_gib() { df -BG --output=avail /home | tail -1 | tr -dc '0-9'; }
healthcode() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1/health" 2>/dev/null; }
startlock_free() { flock -n "$START_LOCK" true 2>/dev/null; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw --format=csv,noheader 2>/dev/null | tr -d ' '; }
mm() { curl -s --max-time 5 "$URL/v1/models" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null; }
model_rev() { docker image inspect "$1" --format '{{index .Config.Labels "tf.tree.manifest"}}' 2>/dev/null; }
model_src() { docker image inspect "$1" --format '{{index .Config.Labels "tf.source"}}' 2>/dev/null; }

run_stop() { log "RUN-STOP $*"; echo "$*" > "$OUT/RUN-STOP"; exit 1; }

restore() {
  local rc=0 code=000 pimg="" i
  if [ "${STOPPED_PROD:-0}" != 1 ]; then
    log "RESTORE skipped: this window never stopped production (/health $(healthcode "$PRODURL"))"
    echo "prod untouched /health $(healthcode "$PRODURL") $(now)" > "$OUT/RESTORED"
    mark RESTORED
    return 0
  fi
  log "RESTORE start $(now)"
  ( cd "$RECIPE" && ./stop.sh ) >> "$OUT/run.log" 2>&1 || true
  ( env -u IMAGE LOCK_HOLDER=0 IMAGE="$PROD_IMAGE" "$PROD_START" </dev/null ) > "$OUT/restore.log" 2>&1 || rc=$?
  for i in $(seq 1 240); do code=$(healthcode "$PRODURL"); [ "$code" = 200 ] && break; sleep 5; done
  pimg=$(docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null || true)
  log "RESTORE prod_rc $rc /health $code image ${pimg:-absent} $(now)"
  echo "prod /health $code (start rc $rc) image ${pimg:-absent} $(now)" > "$OUT/RESTORED"
  curl -s --max-time 10 "$PRODURL/health" > "$OUT/health-restored.json" 2>/dev/null || true
  docker ps --format '{{.Names}} {{.Image}} {{.Status}}' > "$OUT/restored-container.txt" 2>/dev/null || true
  pgrep -af "flock -o .*gpu.lock" > "$OUT/lock-holders-after.txt" 2>/dev/null || true
  if [ "$code" = 200 ]; then
    case "$pimg" in
      *"$PROD_IMAGE"*"$PROD_ID"*) mark PROD-IMAGE-OK; log "PROD-IMAGE ok $pimg" ;;
      *) log "PROD-IMAGE-BAD: \"${pimg:-absent}\" does not carry $PROD_IMAGE $PROD_ID" ;;
    esac
  else
    log "PROD-HEALTH-BAD /health ${code}"
  fi
  mark RESTORED
}

on_exit() {
  local rc=$?
  log "EXIT rc $rc $(now)"
  restore
  log "EXIT-DONE $(now)"
  exit $rc
}

# ---------------------------------------------------------------- preflight

preflight() {
  local n c id load
  for n in "$RECIPE/stop.sh" "$RECIPE/start.sh" "$PROD_START" "$RELABEL"; do
    [ -e "$n" ] || { log "PREFLIGHT-ABORT no $n"; return 9; }
  done
  for n in base.tar.gz ls-tree.z verify_lstree.py verify_manifest.py fp4.manifest int4.manifest Dockerfile.arm \
           Dockerfile.limits ref-env.txt items20.jsonl ref20.json compare.py parse_verdict.py fid_gate.py \
           draft_gate.py quality_client.py qcount.py qverify.py tfm_decode.py qf_harness.py check_dec.py cmp_equal.py \
           x1_bench.py resume_bench.py repro.py SHA256SUMS; do
    [ -f "$IN/$n" ] || { log "PREFLIGHT-ABORT no in/$n"; return 9; }
  done
  for n in prompts/prompts_gsm8k.jsonl prompts/prompts_mmlupro.jsonl prompts/prompts_humaneval.jsonl; do
    [ -f "$IN/$n" ] || { log "PREFLIGHT-ABORT no in/$n"; return 9; }
  done
  [ "$(wc -l < "$IN/items20.jsonl")" = 20 ] || { log "PREFLIGHT-ABORT items20.jsonl is not 20 lines"; return 9; }
  [ "$(ls "$IN"/patches-r5/[0-9]*.patch | wc -l)" = 20 ] || { log "PREFLIGHT-ABORT patches-r5 is not 20 patches"; return 9; }
  [ "$(ls "$IN"/patches-int4/[0-9]*.patch | wc -l)" = 2 ] || { log "PREFLIGHT-ABORT patches-int4 is not 2 patches"; return 9; }
  ( cd "$IN" && python3 checksums.py SHA256SUMS . ) > "$OUT/preflight-in.txt" 2>&1 \
    || { log "PREFLIGHT-ABORT in/SHA256SUMS does not verify: $(tail -3 "$OUT/preflight-in.txt" | tr '\n' ' ')"; return 9; }
  ( cd "$IN/patches-r5" && sha256sum -c --quiet SHA256SUMS ) > "$OUT/preflight-r5.txt" 2>&1 \
    || { log "PREFLIGHT-ABORT patches-r5 SHA256SUMS does not verify"; return 9; }
  ( cd "$IN/patches-int4" && sha256sum -c --quiet SHA256SUMS ) > "$OUT/preflight-int4.txt" 2>&1 \
    || { log "PREFLIGHT-ABORT patches-int4 SHA256SUMS does not verify"; return 9; }
  python3 - "$IN/fp4.manifest" "$IN/int4.manifest" <<'PY' > "$OUT/preflight-manifests.txt" 2>&1
import sys
for p in sys.argv[1:]:
    n = sum(1 for line in open(p, encoding="utf-8") if line.strip())
    print(f"MANIFEST {p} entries {n}")
PY
  grep -q 'MANIFEST .*int4.manifest entries 12625' "$OUT/preflight-manifests.txt" \
    || { log "PREFLIGHT-ABORT the INT4 manifest is not the recorded 12,625 entries"; return 9; }
  grep -q 'MANIFEST .*fp4.manifest entries 12622' "$OUT/preflight-manifests.txt" \
    || { log "PREFLIGHT-ABORT the FP4 manifest is not the staged tree's 12,622 entries"; return 9; }
  docker image inspect "$PROD_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT production image absent"; return 9; }
  docker image inspect "$BASEIMG" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $BASEIMG absent"; return 9; }
  docker image inspect "$BASE_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $BASE_IMAGE absent"; return 9; }
  c=$(docker ps --format '{{.Names}}' | tr '\n' ' ')
  for n in $c; do [ "$n" = "$CN" ] || { log "FOREIGN-CONTAINER $n is running: this window will not touch it"; return 9; }; done
  id=$(docker inspect "$CN" --format '{{.Image}}' 2>/dev/null || true)
  if [ -n "$id" ] && [ "$id" = "$PROD_ID" ] && [ "$(healthcode "$PRODURL")" = 200 ]; then
    log "PREFLIGHT production up and pinned $id /health 200"
  elif [ -z "$id" ] && [ -z "$c" ]; then
    PREFLIGHT_PROD_DOWN=1
    log "PREFLIGHT-NOTE production is not running and nothing else is: this window must restore it on the way out"
  else
    log "PREFLIGHT-ABORT production container image \"${id:-absent}\" /health $(healthcode "$PRODURL") is not the pinned $PROD_ID"
    return 9
  fi
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -q '^HF_HOME=' \
    || log "PREFLIGHT-NOTE production container has no HF_HOME line"
  startlock_free || { log "PREFLIGHT-ABORT start.lock is held"; return 9; }
  [ "$(free_gib)" -ge "$DISK_MIN" ] || { log "PREFLIGHT-ABORT home free $(free_gib) GiB"; return 9; }
  log "PREFLIGHT-NOTE MemAvailable $(memavail) GiB with production still up"
  load=$(cut -d' ' -f1 /proc/loadavg)
  awk -v l="$load" 'BEGIN{exit !(l < 14)}' || { log "PREFLIGHT-ABORT load $load"; return 9; }
  log "PREFLIGHT host $(uname -r) gpu [$(gpu)] load $load disk $(free_gib) GiB mem $(memavail) GiB"
  log "PREFLIGHT script $(sha256sum "$SELF" | cut -d' ' -f1)"
  mark PREFLIGHT-OK
  return 0
}

record_prod() {
  local d=$OUT/P
  mkdir -p "$d"
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$PRODURL/health" > "$d/health.json" 2>/dev/null || true
  curl -s --max-time 10 "$PRODURL/v1/models" > "$d/models.json" 2>/dev/null || true
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CN" 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd.txt" 2>/dev/null || true
  log "PROD-BEFORE image $(cat "$d/image.txt" 2>/dev/null) health $(healthcode "$PRODURL")"
}

stop_prod() {
  local i
  ( cd "$RECIPE" && ./stop.sh ) >> "$OUT/run.log" 2>&1 || true
  for i in $(seq 1 30); do [ -z "$(docker ps -q)" ] && [ "$(healthcode "$PRODURL")" != 200 ] && break; sleep 2; done
  STOPPED_PROD=1
  log "STOPPED production :8888 $(healthcode "$PRODURL") containers [$(docker ps --format '{{.Names}}' | tr '\n' ' ')] mem $(memavail) GiB"
}

# ---------------------------------------------------------------- staging and build

stage_tree() { # arm patchdir... : extract, ls-tree, apply, manifest
  local arm=$1
  shift
  local tree=$TREES/$arm/src p n=0 man
  if [ "$arm" = A ]; then man=$IN/fp4.manifest; else man=$IN/int4.manifest; fi
  if [ -f "$MARKS/STAGE-$arm-OK" ] && [ -d "$tree" ] \
     && python3 "$IN/verify_manifest.py" "$man" "$tree" 2>/dev/null | grep -q 'mismatches 0 extra_files 0'; then
    log "SKIP stage $arm (marker and manifest verify)"
    return 0
  fi
  rm -rf "$TREES/$arm"
  mkdir -p "$tree"
  tar -xzf "$IN/base.tar.gz" -C "$tree" || { log "STAGE-$arm extract failed"; return 1; }
  python3 "$IN/verify_lstree.py" "$IN/ls-tree.z" "$tree" > "$OUT/stage-$arm-base.txt" 2>&1 \
    || { log "STAGE-$arm base: $(head -1 "$OUT/stage-$arm-base.txt")"; return 1; }
  grep -q 'missing 0 mismatch 0 extra 0 mode_bad 0' "$OUT/stage-$arm-base.txt" \
    || { log "STAGE-$arm base refused: $(head -1 "$OUT/stage-$arm-base.txt")"; return 1; }
  for p in "$@"; do
    for f in "$IN/$p"/[0-9]*.patch; do
      ( cd "$tree" && GIT_CEILING_DIRECTORIES="$BOX" git -c core.autocrlf=false -c core.eol=lf apply \
          --whitespace=nowarn "$f" ) || { log "STAGE-$arm APPLY-FAIL $(basename "$f")"; return 1; }
      n=$((n + 1))
    done
  done
  python3 "$IN/verify_manifest.py" "$man" "$tree" > "$OUT/stage-$arm-head.txt" 2>&1 \
    || { log "STAGE-$arm manifest: $(head -1 "$OUT/stage-$arm-head.txt")"; return 1; }
  grep -q 'mismatches 0 extra_files 0' "$OUT/stage-$arm-head.txt" \
    || { log "STAGE-$arm manifest refused: $(head -1 "$OUT/stage-$arm-head.txt")"; return 1; }
  log "STAGE-$arm ok patches $n $(head -1 "$OUT/stage-$arm-base.txt") / $(head -1 "$OUT/stage-$arm-head.txt")"
  mark "STAGE-$arm-OK"
  return 0
}

build_image() { # arm tree tag srcsha manifest
  local arm tree tag srcsha man rc=0 id files t0 msha
  arm=$1; tree=$2; tag=$3; srcsha=$4; man=$5
  msha=$(sha256sum "$man" | cut -d' ' -f1)
  if docker image inspect "$tag" > /dev/null 2>&1; then
    if [ "$(model_rev "$tag")" = "$msha" ] && [ "$(model_src "$tag")" = "$srcsha" ]; then
      id=$(docker image inspect "$tag" --format '{{.Id}}')
      echo "$id" > "$OUT/image-$arm.id"
      log "SKIP build $arm: $tag id $id carries tf.tree.manifest $msha and tf.source $srcsha"
      mark "BUILD-$arm-OK"
      return 0
    fi
    log "BUILD-$arm tag $tag exists but its labels are [$(model_rev "$tag")] [$(model_src "$tag")], rebuilding"
    docker rmi "$tag" > /dev/null 2>&1 || true
  fi
  rm -rf "$BOX/serve-$arm"
  mkdir -p "$BOX/serve-$arm"
  cp -a "$tree" "$BOX/serve-$arm/src"
  cp "$IN/Dockerfile.arm" "$BOX/serve-$arm/Dockerfile.arm"
  [ "$(free_gib)" -ge "$DISK_MIN" ] || { log "DISK-LOW $(free_gib) GiB before build $arm"; return 1; }
  files=$(cd "$BOX/serve-$arm/src" && find . -type f | wc -l)
  t0=$(date +%s)
  docker build --progress=plain --memory 24g --memory-swap 32g --cpu-quota 1200000 -t "$tag" \
    --label "tf.tree.manifest=$msha" --label "tf.source=$srcsha" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg BASEIMG="$BASEIMG" \
    --build-arg ZIG_VERSION="$ZIG_VERSION" --build-arg ZIG_SHA256="$ZIG_SHA256" \
    --build-arg SRC_SHA="$srcsha" -f "$BOX/serve-$arm/Dockerfile.arm" "$BOX/serve-$arm" > "$OUT/build-$arm.log" 2>&1 || rc=$?
  echo "build_rc $rc wall_s $(( $(date +%s) - t0 )) files $files $(now)" > "$OUT/build-$arm.txt"
  [ "$rc" = 0 ] || { log "BUILD-$arm-FAIL rc $rc $(tail -3 "$OUT/build-$arm.log" | tr '\n' ' ')"; return 1; }
  grep -q "SOURCE $srcsha" "$OUT/build-$arm.log" || { log "BUILD-$arm no SOURCE line"; return 1; }
  grep -q "BUILD OK" "$OUT/build-$arm.log" || { log "BUILD-$arm no BUILD OK"; return 1; }
  id=$(docker image inspect "$tag" --format '{{.Id}}')
  echo "$id" > "$OUT/image-$arm.built-id"
  bash "$RELABEL" "$tag" embedded >> "$OUT/build-$arm.log" 2>&1 || { log "BUILD-$arm relabel failed"; return 1; }
  id=$(docker image inspect "$tag" --format '{{.Id}}')
  [ -n "$id" ] || { log "BUILD-$arm no image id after relabel"; return 1; }
  echo "$id" > "$OUT/image-$arm.id"
  [ "$(docker image inspect "$tag" --format '{{index .Config.Labels "tf.kernels"}}')" = embedded ] \
    || { log "BUILD-$arm label is not embedded"; return 1; }
  [ "$(model_rev "$tag")" = "$msha" ] || { log "BUILD-$arm lost tf.tree.manifest"; return 1; }
  [ "$(model_src "$tag")" = "$srcsha" ] || { log "BUILD-$arm lost tf.source"; return 1; }
  docker image inspect "$tag" --format '{{.Created}} {{index .Config.Labels "tf.kernels"}} {{index .Config.Labels "tf.tree.manifest"}} {{index .Config.Labels "tf.source"}}' > "$OUT/image-$arm.labels"
  log "BUILT $tag id $id manifest $msha source $srcsha wall $(( $(date +%s) - t0 ))s"
  mark "BUILD-$arm-OK"
  return 0
}

image_id() { cat "$OUT/image-$1.id" 2>/dev/null; }

# ---------------------------------------------------------------- boot

expected_env() { # dir delta
  local d=$1 delta=$2 e name
  cp "$IN/ref-env.txt" "$d/env-expected.txt"
  for e in $delta; do
    case "$e" in
      TF_*=*|TENSORFOLD_*=*)
        name=${e%%=*}
        if grep -q "^$name=" "$d/env-expected.txt"; then
          sed -i "s|^$name=.*|$e|" "$d/env-expected.txt"
        else
          echo "$e" >> "$d/env-expected.txt"
        fi
        ;;
    esac
  done
  sort -o "$d/env-expected.txt" "$d/env-expected.txt"
}

banner_gate() { # label dir par ctx ckpt drafts
  local label=$1 d=$2 par=$3 ctx=$4 ckpt=$5 drafts=$6 want_drafts want_model want_rev rows
  grep -qa -- "${par} at once · ${ctx}-token window · bf16 KV" "$d/boot.log" \
    || { log "SETTINGS $label: the window line is not '${par} at once · ${ctx}-token window · bf16 KV'"; return 2; }
  if [ "$drafts" = 0 ]; then want_drafts="drafts off"; else want_drafts="drafts MTP"; fi
  grep -qa -- "· $want_drafts · port 8080" "$d/boot.log" || { log "SETTINGS $label: no '$want_drafts'"; return 2; }
  if [ "$ckpt" = int4 ]; then want_model=$MODEL_B; want_rev=${REV_B:0:8}; else want_model=$MODEL_A; want_rev=${REV_A:0:8}; fi
  grep -qa "Model    $want_model @ $want_rev" "$d/boot.log" \
    || { log "CHECKPOINT-GATE $label: no 'Model    $want_model @ $want_rev' line"; return 3; }
  grep -qa -- "--no-thinking" "$d/cmd.txt" || { log "SETTINGS $label: Cmd lacks --no-thinking"; return 4; }
  grep -qa -- '--kv-cache","bf16' "$d/cmd.txt" || { log "SETTINGS $label: Cmd lacks --kv-cache bf16"; return 4; }
  if [ "$ckpt" = int4 ]; then
    grep -qa "$SUB_B/snapshots/$REV_B" "$d/cmd.txt" || { log "CHECKPOINT-GATE $label: Cmd lacks $SUB_B/$REV_B"; return 4; }
  else
    grep -qa "$SUB_A/snapshots/$REV_A" "$d/cmd.txt" || { log "CHECKPOINT-GATE $label: Cmd lacks $SUB_A/$REV_A"; return 4; }
  fi
  python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1],encoding="utf-8")).get("status")=="ok" else 1)' "$d/health.json" 2>/dev/null \
    || { log "HEALTH-GATE $label: $(head -c 200 "$d/health.json" 2>/dev/null | tr '\n' ' ')"; return 5; }
  [ "$(cat "$d/model.txt" 2>/dev/null)" = "$MODEL" ] || { log "MODEL-GATE $label: [$(cat "$d/model.txt" 2>/dev/null)]"; return 5; }
  rows=$(grep -aho 'prompts in passes of up to [0-9]* rows' "$d/seqline.txt" "$d/boot.log" 2>/dev/null | head -1 | sed 's/.*up to //; s/ rows//')
  [ -n "$rows" ] || { log "SETTINGS $label: no 'prompts in passes of up to' line"; return 6; }
  [ "$ROWS_WANT" = any ] || [ "$rows" = "$ROWS_WANT" ] \
    || { log "SETTINGS $label: pass rows $rows, expected $ROWS_WANT"; return 6; }
  return 0
}

boot_ok() { # label: reusable only when the boot passed and the step that needs its serve is complete
  local label=$1
  [ -f "$MARKS/BOOT-$label-OK" ] || return 1
  if [ -z "${BOOT_NEED:-}" ] || [ ! -f "$MARKS/$BOOT_NEED" ]; then
    log "BOOT-RENEW $label: ${BOOT_NEED:-no step marker}, so this boot must serve again"
    return 1
  fi
  [ -s "$OUT/$label/env-diff.txt" ] && return 1
  return 0
}

keep_raw() { # d: keep d/raw across the boot's rm -rf, restored at the SAME path
  local d=$1 keep=""
  if [ -d "$d/raw" ]; then
    keep="$d.raw.keep.$$"
    mv "$d/raw" "$keep" || return 1
  fi
  rm -rf "$d"; mkdir -p "$d"
  if [ -n "$keep" ] && [ -d "$keep" ]; then mv "$keep" "$d/raw" || return 1; fi
  mkdir -p "$d/raw"
}

run_boot() { # label img imgid par ctx ckpt drafts delta
  local label img imgid par ctx ckpt drafts delta d rc=0 i model t0
  label=$1; img=$2; imgid=$3; par=$4; ctx=$5; ckpt=$6; drafts=$7; delta=$8
  d=$OUT/$label
  if boot_ok "$label"; then log "SKIP boot $label (marker and empty env diff)"; return 0; fi
  keep_raw "$d" || { log "BOOT $label: cannot set aside $d/raw"; return 1; }
  printf '%s\n' "$delta" > "$d/delta.txt"
  expected_env "$d" "$delta"
  startlock_free || { log "START-LOCK held before $label"; echo start_lock_conflict > "$d/START-LOCK"; return 9; }
  local -a DARGS=()
  [ -n "$delta" ] && read -r -a DARGS <<< "$delta"
  t0=$(date +%s)
  ( cd "$RECIPE" && timeout 2400 env "${DARGS[@]}" PREPARE=0 IMAGE="$img" CHECKPOINT="$ckpt" \
      VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL="$par" CONTEXT="$ctx" HOST=127.0.0.1 \
      PORT=8080 MEM_CHECK=0 THINKING=0 DRAFTS="$drafts" WAIT_TIMEOUT=1800 ./start.sh restart </dev/null ) \
      > "$d/boot.log" 2>&1 || rc=$?
  echo "boot_rc $rc wall_s $(( $(date +%s) - t0 )) $(now)" > "$d/boot_time.txt"
  if grep -q "another ./start.sh is already running" "$d/boot.log" 2>/dev/null; then
    log "START-LOCK $label from start.sh"; echo start_lock_conflict > "$d/START-LOCK"; return 9
  fi
  if [ "$rc" != 0 ]; then log "BOOT $label rc $rc $(tail -3 "$d/boot.log" | tr '\n' ' ')"; return 1; fi
  for i in $(seq 1 120); do model=$(mm); [ -n "$model" ] && break; sleep "$POLL"; done
  [ -n "$model" ] || { log "MODEL empty $label"; return 1; }
  echo "$model" > "$d/model.txt"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CN" 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/container-image.txt" 2>/dev/null || true
  docker logs "$CN" > "$d/server.log" 2>&1 || true
  docker logs "$CN" 2>&1 | grep -a -m1 -o 'prompts in passes of up to [0-9]* rows' > "$d/seqline.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$d/health.json" 2>/dev/null || true
  curl -s --max-time 10 "$URL/v1/models" > "$d/models.json" 2>/dev/null || true
  diff -u "$d/env-expected.txt" "$d/env.txt" > "$d/env-diff.txt" 2>&1 \
    || { log "ENV-GATE $label: the container environment differs ($(head -3 "$d/env-diff.txt" | tr '\n' ' '))"; return 3; }
  grep -q -- "$imgid" "$d/container-image.txt" 2>/dev/null \
    || { log "IMAGE-GATE $label: $(cat "$d/container-image.txt" 2>/dev/null) lacks $imgid"; return 3; }
  banner_gate "$label" "$d" "$par" "$ctx" "$ckpt" "$drafts" || return 4
  log "BOOT $label ok $(now) wall $(( $(date +%s) - t0 ))s $(gpu) delta [$delta]"
  mark "BOOT-$label-OK"
  return 0
}

sanity() { # label dir
  local label=$1 d=$2 r
  r=$(curl -s --max-time 300 "$URL/v1/chat/completions" -H 'Content-Type: application/json' \
       -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Reply with OK."}],"max_tokens":8,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}')
  echo "$r" > "$d/sanity.json"
  echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); c=r["choices"][0]["message"].get("content") or ""; assert c.strip(), "empty"; print("SANITY ok", repr(c[:20]), r["usage"]["completion_tokens"])' \
      >> "$d/sanity.txt" 2>&1 || { log "SANITY $label failed"; return 1; }
  log "SANITY $label ok"
}

stop_arm() {
  local i
  ( cd "$RECIPE" && ./stop.sh ) >> "$OUT/run.log" 2>&1 || true
  for i in $(seq 1 30); do [ -z "$(docker ps -q)" ] && break; sleep 2; done
}

arm_boot() { # label img imgid par ctx ckpt drafts delta
  local label=$1 i brc ok=0
  for i in 1 2; do
    run_boot "$@" && { ok=1; break; }
    brc=$?
    if [ -f "$OUT/$label/START-LOCK" ]; then stop_arm; run_stop "start.lock conflict at $label"; fi
    log "ARM-FAIL $label rc $brc attempt $i"
    [ "$i" = 2 ] && break
    stop_arm
  done
  [ "$ok" = 1 ] || { stop_arm; run_stop "two consecutive boot failures at $label"; }
  sanity "$label" "$OUT/$label" || { stop_arm; run_stop "sanity failed at $label"; }
  return 0
}

# ---------------------------------------------------------------- quality

quality_arm() { # arm img imgid ckpt
  local arm img imgid ckpt d bench rc=0
  arm=$1; img=$2; imgid=$3; ckpt=$4
  d=$OUT/Q$arm
  if [ -f "$MARKS/QUAL-$arm-OK" ] && [ -f "$MARKS/FID-$arm-OK" ] && [ -d "$d/raw" ] \
     && python3 "$IN/qcount.py" "$d/raw" > /dev/null 2>&1; then
    log "SKIP quality $arm (marker and all three raw files complete)"
    ( cd "$d/raw" && sha256sum gsm8k.jsonl mmlupro.jsonl humaneval.jsonl ) >> "$OUT/run.log" 2>/dev/null || true
    return 0
  fi
  BOOT_NEED="QUAL-$arm-OK"
  arm_boot "Q$arm" "$img" "$imgid" 4 131072 "$ckpt" 1 "$BLOCK_ALL" || return 1
  mkdir -p "$d/raw"
  ( cd "$IN" && python3 quality_client.py --base "$URL" --model "$MODEL" --arm "FID$arm" --bench gsm8k \
      --prompts "$IN/items20.jsonl" --out "$d/raw/gsm8k20.jsonl" --concurrency "$CONC" --timeout 1800 ) \
      > "$d/fid-client.out" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { stop_arm; run_stop "the 20-item client failed at arm $arm (rc $rc)"; }
  python3 "$IN/compare.py" --raw "$d/raw/gsm8k20.jsonl" --ref "$IN/ref20.json" --out "$d/verdict.json" \
      > "$d/verdict.txt" 2>&1 || { stop_arm; run_stop "compare.py refused the 20 raw rows at arm $arm: $(tail -2 "$d/verdict.txt" | tr '\n' ' ')"; }
  if [ "$arm" = A ]; then
    # Arm A keeps its external gate: QCMPB is like for like on every serve axis the banner shows.
    python3 "$IN/fid_gate.py" "$d/verdict.json" QCMPB 20 >> "$d/verdict.txt" 2>&1 \
        || { tail -20 "$d/verdict.txt" >> "$OUT/run.log"; stop_arm; run_stop "FIDELITY GATE FAILED at arm A vs QCMPB: the arm is void"; }
    tail -4 "$d/verdict.txt" >> "$OUT/run.log"
  else
    # Arm B's gate is internal: its own drafted replies against its own "draft": false replies, same boot, same
    # 20 prompts, token ids and token sha from the server. QCMPA ran 8 slots, a 262144-token window, vision on,
    # int4_prompt_kernel, 32-row lm_head tiles and DRAFT_INT4, so it is a different arithmetic path and never a
    # reference for this port's own arithmetic.
    rm -f "$d/draft-gate.txt"
    python3 "$IN/draft_gate.py" --base "$URL" --model "$MODEL" --items "$IN/items20.jsonl" \
        --out-dir "$d/draft" --concurrency "$CONC" --timeout 1800 > "$d/draft-gate.txt" 2>&1 \
        || { tail -20 "$d/draft-gate.txt" >> "$OUT/run.log"; stop_arm; run_stop "INTERNAL EXACTNESS GATE FAILED at arm B: drafted != draft:false on the 20-item oracle"; }
    grep -E '^SUMMARY|^DRAFT-OK' "$d/draft-gate.txt" >> "$OUT/run.log"
    tail -3 "$d/verdict.txt" >> "$OUT/run.log"
  fi
  mark "FID-$arm-OK"
  for bench in gsm8k mmlupro humaneval; do
    rc=0
    ( cd "$IN" && python3 quality_client.py --base "$URL" --model "$MODEL" --arm "$arm" --bench "$bench" \
        --prompts "$IN/prompts/prompts_$bench.jsonl" --out "$d/raw/$bench.jsonl" --concurrency "$CONC" --timeout 1800 ) \
        > "$d/q-$bench.out" 2>&1 || rc=$?
    [ "$rc" = 0 ] || { stop_arm; run_stop "quality client failed at arm $arm bench $bench (rc $rc)"; }
    log "QUAL $arm $bench $(tail -1 "$d/q-$bench.out")"
  done
  python3 "$IN/qcount.py" "$d/raw" > "$d/qcount.txt" 2>&1 \
    || { cat "$d/qcount.txt" >> "$OUT/run.log"; stop_arm; run_stop "quality raw is short or carries errors at arm $arm"; }
  cat "$d/qcount.txt" >> "$OUT/run.log"
  mark "QUAL-$arm-OK"
  stop_arm
  log "QUAL $arm done $(now)"
  return 0
}

# ---------------------------------------------------------------- speed

speed_cell() { # arm ckpt img imgid streams rep
  local arm ckpt img imgid st rep label d par ctx rows rc=0
  arm=$1; ckpt=$2; img=$3; imgid=$4; st=$5; rep=$6
  label="S$arm-D$st-b$rep"
  d=$OUT/$label
  par=4; ctx=131072; ROWS_WANT=3072
  [ "$st" = 8 ] && { par=8; ctx=32768; ROWS_WANT=any; }
  rows=$((2 * PASSES * st))
  if [ -f "$MARKS/SPEED-$label-OK" ] && [ -s "$d/dec.jsonl" ] \
     && python3 "$IN/check_dec.py" "$d/dec.jsonl" "$rows" > /dev/null 2>&1; then
    log "SKIP speed $label (marker and rows check)"
    return 0
  fi
  BOOT_NEED="SPEED-$label-OK"
  arm_boot "$label" "$img" "$imgid" "$par" "$ctx" "$ckpt" 1 "$BLOCK_ALL" || return 1
  ROWS_WANT=3072
  rm -f "$d/dec.jsonl" "$d/check.txt"
  ( cd "$IN" && API_URL="$URL" MODEL_NAME="$MODEL" python3 tfm_decode.py "$label" "$st" "$d/dec.jsonl" \
      "$PASSES" prose,code ) > "$d/dec.out" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { stop_arm; run_stop "tfm_decode failed at $label (rc $rc)"; }
  python3 "$IN/check_dec.py" "$d/dec.jsonl" "$rows" > "$d/check.txt" 2>&1 \
    || { cat "$d/check.txt" >> "$OUT/run.log"; stop_arm; run_stop "decode cell $label is short or unmeasured"; }
  cat "$d/check.txt" >> "$OUT/run.log"
  grep '^DEC' "$d/dec.out" >> "$OUT/run.log"
  mark "SPEED-$label-OK"
  stop_arm
  return 0
}

# ---------------------------------------------------------------- exactness

x1_arm() { # arm img imgid ckpt
  local arm img imgid ckpt d rc=0
  arm=$1; img=$2; imgid=$3; ckpt=$4
  d=$OUT/X1$arm
  if [ -f "$MARKS/X1-$arm-OK" ] && [ -s "$d/x1.json" ] && [ -s "$d/repro.json" ]; then
    log "SKIP X1 $arm (marker and data)"
    return 0
  fi
  BOOT_NEED="X1-$arm-OK"
  arm_boot "X1$arm" "$img" "$imgid" 4 131072 "$ckpt" 1 "$BLOCK_ALL" || return 1
  mkdir -p "$d"
  ( cd "$IN" && python3 resume_bench.py "$URL" "$MODEL" --tokens 8192 --against 14 --output "$d/resume-orig.json" ) \
      > "$d/resume-orig.out" 2>&1 || { stop_arm; run_stop "resume_bench failed at arm $arm"; }
  ( cd "$IN" && python3 x1_bench.py "$URL" "$MODEL" --tokens 8192 --fillers 14 --output "$d/x1.json" ) \
      > "$d/x1.out" 2>&1 || { cat "$d/x1.out" >> "$OUT/run.log"; stop_arm; run_stop "X1 resumed-equals-fresh FAILED at arm $arm"; }
  ( cd "$IN" && python3 repro.py "$URL" "$MODEL" --runs 3 --warm 2 --container "$CN" --output "$d/repro.json" ) \
      > "$d/repro.out" 2>&1 || { cat "$d/repro.out" >> "$OUT/run.log"; stop_arm; run_stop "repro.py FAILED at arm $arm"; }
  tail -3 "$d/x1.out" >> "$OUT/run.log"
  grep -E '^RUN' "$d/repro.out" >> "$OUT/run.log"
  mark "X1-$arm-OK"
  stop_arm
  return 0
}

x2_arm() { # arm img imgid ckpt
  local arm img imgid ckpt d ref
  arm=$1; img=$2; imgid=$3; ckpt=$4
  d=$OUT/X2$arm
  if [ -f "$MARKS/X2-$arm-OK" ]; then log "SKIP X2 $arm (marker)"; return 0; fi
  BOOT_NEED="X2-$arm-OK"
  arm_boot "X2$arm" "$img" "$imgid" 4 131072 "$ckpt" 0 "DRAFTS=0 $BLOCK_ALL" || return 1
  mkdir -p "$d"
  rm -f "$d/dec.jsonl" "$d/cmp-1.txt" "$d/cmp-4.txt"
  ( cd "$IN" && API_URL="$URL" MODEL_NAME="$MODEL" python3 tfm_decode.py "X2$arm" 1 "$d/dec.jsonl" \
      "$PASSES" prose,code ) > "$d/dec-1.out" 2>&1 || { stop_arm; run_stop "X2 decode C=1 failed at arm $arm"; }
  ( cd "$IN" && API_URL="$URL" MODEL_NAME="$MODEL" python3 tfm_decode.py "X2$arm" 4 "$d/dec.jsonl" \
      "$PASSES" prose,code ) > "$d/dec-4.out" 2>&1 || { stop_arm; run_stop "X2 decode C=4 failed at arm $arm"; }
  python3 "$IN/check_dec.py" "$d/dec.jsonl" $((2 * PASSES * (1 + 4))) > "$d/check.txt" 2>&1 \
    || { cat "$d/check.txt" >> "$OUT/run.log"; stop_arm; run_stop "X2 rows are short at arm $arm"; }
  python3 "$IN/cmp_equal.py" "$OUT/S$arm-D1-b1/dec.jsonl" "$d/dec.jsonl" 1 > "$d/cmp-1.txt" 2>&1 \
    || { cat "$d/cmp-1.txt" >> "$OUT/run.log"; stop_arm; run_stop "X2 drafted-vs-plain FAILED at arm $arm C=1"; }
  python3 "$IN/cmp_equal.py" "$OUT/S$arm-D4-b1/dec.jsonl" "$d/dec.jsonl" 4 > "$d/cmp-4.txt" 2>&1 \
    || { cat "$d/cmp-4.txt" >> "$OUT/run.log"; stop_arm; run_stop "X2 drafted-vs-plain FAILED at arm $arm C=4"; }
  cat "$d/cmp-1.txt" "$d/cmp-4.txt" >> "$OUT/run.log"
  mark "X2-$arm-OK"
  stop_arm
  return 0
}

x3_arm() { # arm img imgid ckpt
  local arm img imgid ckpt d
  arm=$1; img=$2; imgid=$3; ckpt=$4
  d=$OUT/X3$arm
  if [ -f "$MARKS/X3-$arm-OK" ]; then log "SKIP X3 $arm (marker)"; return 0; fi
  BOOT_NEED="X3-$arm-OK"
  arm_boot "X3$arm" "$img" "$imgid" 4 131072 "$ckpt" 1 "$BLOCK_NOSD" || return 1
  mkdir -p "$d"
  rm -f "$d/dec.jsonl" "$d/cmp.txt"
  ( cd "$IN" && API_URL="$URL" MODEL_NAME="$MODEL" python3 tfm_decode.py "X3$arm" 4 "$d/dec.jsonl" \
      "$PASSES" prose,code ) > "$d/dec.out" 2>&1 || { stop_arm; run_stop "X3 decode failed at arm $arm"; }
  python3 "$IN/check_dec.py" "$d/dec.jsonl" $((2 * PASSES * 4)) > "$d/check.txt" 2>&1 \
    || { cat "$d/check.txt" >> "$OUT/run.log"; stop_arm; run_stop "X3 rows are short at arm $arm"; }
  python3 "$IN/cmp_equal.py" "$OUT/S$arm-D4-b1/dec.jsonl" "$d/dec.jsonl" 4 > "$d/cmp.txt" 2>&1 \
    || { cat "$d/cmp.txt" >> "$OUT/run.log"; stop_arm; run_stop "X3 shared-rounds FAILED at arm $arm"; }
  cat "$d/cmp.txt" >> "$OUT/run.log"
  mark "X3-$arm-OK"
  stop_arm
  return 0
}

quality_verify() {
  if [ -f "$MARKS/QVERIFY-OK" ]; then log "SKIP qverify (marker)"; return 0; fi
  python3 "$IN/qverify.py" "$OUT" > "$OUT/verify-quality.txt" 2>&1 \
    || { cat "$OUT/verify-quality.txt" >> "$OUT/run.log"; run_stop "the 1,664 bodies are not the frozen bodies on both arms"; }
  cat "$OUT/verify-quality.txt" >> "$OUT/run.log"
  mark QVERIFY-OK
  return 0
}

# ---------------------------------------------------------------- run

window() {
  : > "$OUT/ARMS"; : > "$OUT/ORACLE.tsv"
  rm -f "$OUT"/RUN-STOP "$OUT"/RUN-DONE
  echo "LOCKED $(now) pid $$ recipe $RECIPE" > "$OUT/LOCKED"
  log "LOCKED $(now) pid $$"
  log "SCRIPT window.sh sha256 $(sha256sum "$SELF" | cut -d' ' -f1)"
  log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); $(nvidia-smi --query-gpu=name,compute_cap,driver_version,memory.total --format=csv,noheader 2>/dev/null); RAM $(free -g | awk '/^Mem:/{print $2}') GiB"
  trap on_exit EXIT
  trap 'exit 130' INT TERM HUP
  preflight || run_stop "preflight refused: leaving everything as found"
  if [ "$PREFLIGHT_PROD_DOWN" = 1 ]; then
    STOPPED_PROD=1
    log "PREFLIGHT production was down: the EXIT trap will restore it"
  fi
  if [ "$STOPPED_PROD" = 0 ]; then record_prod; fi
  stop_prod
  [ "$(memavail)" -ge 20 ] || run_stop "only $(memavail) GiB free after production stopped"

  stage_tree A patches-r5 || run_stop "stage A failed"
  stage_tree B patches-r5 patches-int4 || run_stop "stage B failed"
  build_image A "$TREES/A/src" "$IMG_A" "$BASE+r5-0001-0020" "$IN/fp4.manifest" || run_stop "image A build failed"
  build_image B "$TREES/B/src" "$IMG_B" "$BASE+r5-0001-0020+int4-0021-0022" "$IN/int4.manifest" || run_stop "image B build failed"
  log "IMAGES A $(image_id A) B $(image_id B)"

  quality_arm A "$IMG_A" "$(image_id A)" nvfp4 || run_stop "arm A quality failed"
  quality_arm B "$IMG_B" "$(image_id B)" int4 || run_stop "arm B quality failed"

  local st rep arm
  for st in 1 4 8; do
    speed_cell A nvfp4 "$IMG_A" "$(image_id A)" "$st" 1 || run_stop "speed cell A D$st b1 failed"
    speed_cell B int4 "$IMG_B" "$(image_id B)" "$st" 1 || run_stop "speed cell B D$st b1 failed"
    speed_cell B int4 "$IMG_B" "$(image_id B)" "$st" 2 || run_stop "speed cell B D$st b2 failed"
    speed_cell A nvfp4 "$IMG_A" "$(image_id A)" "$st" 2 || run_stop "speed cell A D$st b2 failed"
  done

  x1_arm A "$IMG_A" "$(image_id A)" nvfp4 || run_stop "X1 A failed"
  x1_arm B "$IMG_B" "$(image_id B)" int4 || run_stop "X1 B failed"
  x2_arm A "$IMG_A" "$(image_id A)" nvfp4 || run_stop "X2 A failed"
  x2_arm B "$IMG_B" "$(image_id B)" int4 || run_stop "X2 B failed"
  x3_arm A "$IMG_A" "$(image_id A)" nvfp4 || run_stop "X3 A failed"
  x3_arm B "$IMG_B" "$(image_id B)" int4 || run_stop "X3 B failed"

  quality_verify || run_stop "quality body verification failed"
  mark RUN-DONE
  log "RUN-DONE $(now) quality A and B, 12 speed boots, X1-X3 on both arms, bodies verified"
  exit 0
}

# ---------------------------------------------------------------- selftest (stubs: no docker, no GPU)

local_scope_check() { # file
  python3 - "$1" <<'PY'
import re
import sys
bad = []
for n, line in enumerate(open(sys.argv[1], encoding="utf-8").read().splitlines(), 1):
    s = line.strip()
    if not s.startswith("local "):
        continue
    for name in re.findall(r"(?:^local\s+|[\s])([A-Za-z_][A-Za-z0-9_]*)=", s):
        if re.search(r"\$(?:\{" + re.escape(name) + r"\b|" + re.escape(name) + r"\b)", s):
            bad.append(f"{n}: {name}")
if bad:
    print("local-scope: " + ", ".join(bad))
    sys.exit(1)
PY
}

selftest() {
  local d=$OUT/selftest rc=0
  rm -rf "$d"; mkdir -p "$d"
  # 1. the env gate
  printf 'TF_A=1\nTF_B=2\n' > "$d/env-a.txt"
  printf 'TF_A=1\nTF_B=3\n' > "$d/env-b.txt"
  cp "$d/env-a.txt" "$d/env-a2.txt"
  mkdir -p "$d/ee"
  expected_env "$d/ee" "$BLOCK_ALL"
  grep -q '^TF_FLASHNEXT_CONFIDENCE=-0.15$' "$d/ee/env-expected.txt" \
    || { echo "SELFTEST-FAIL the block did not override the recipe default"; rc=1; }
  grep -q '^TF_FLASHNEXT_SHARED_DRAFTS=0$' "$d/ee/env-expected.txt" \
    || { echo "SELFTEST-FAIL the block did not add SHARED_DRAFTS"; rc=1; }
  [ "$(grep -c . "$d/ee/env-expected.txt")" = "$(grep -c . "$IN/ref-env.txt")" ] \
    && { echo "SELFTEST-FAIL the block added no new line to the expected env"; rc=1; }
  echo "SELFTEST-OPEN env (block overrides CONFIDENCE and adds SHARED_DRAFTS: $(grep -c . "$d/ee/env-expected.txt") lines)"
  diff -u "$d/env-a.txt" "$d/env-a2.txt" > "$d/env-same.txt" 2>&1 \
    || { echo "SELFTEST-FAIL env gate rejects equal blocks"; rc=1; }
  diff -u "$d/env-a.txt" "$d/env-b.txt" > "$d/env-diff.txt" 2>&1 && { echo "SELFTEST-FAIL env gate accepts a changed line"; rc=1; }
  # 2. the banner gate: one good boot and each gate's own break
  local b=$d/boot
  mkdir -p "$b"
  cat > "$b/boot.log" <<'LOG'
Qwen3.8-Flash-Next · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080
    Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8)
    Window   131072 tokens · 4 at once · bf16 KV · drafts MTP
[5/5] Smoke test: one chat completion
LOG
  printf '["tensorfold-native","serve","/root/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300","--name","Qwen3.8-Flash-Next","--host","127.0.0.1","--port","8080","--context","131072","--parallel","4","--no-thinking","--kv-cache","bf16"]\n' > "$b/cmd.txt"
  printf '{"status":"ok"}\n' > "$b/health.json"
  printf 'Qwen3.8-Flash-Next\n' > "$b/model.txt"
  printf 'prompts in passes of up to 3072 rows\n' > "$b/seqline.txt"
  banner_gate good "$b" 4 131072 nvfp4 1 > "$d/banner-good.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the banner gate rejected a good boot: $(cat "$d/banner-good.txt")"; rc=1; }
  echo "SELFTEST-OPEN banner (FP4 identity, MTP drafts, 4 at once, 131072 tokens, bf16, rows 3072)"
  for mut in "4 at once|5 at once|boot.log" "131072-token window|32768-token window|boot.log" \
             "drafts MTP|drafts off|boot.log" "--no-thinking|--thinking|cmd.txt" \
             "--kv-cache\",\"bf16|--kv-cache\",\"fp8|cmd.txt" "Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6|Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741|boot.log" \
             "up to 3072 rows|up to 1536 rows|seqline.txt"; do
    old=${mut%%|*}; rest=${mut#*|}; new=${rest%%|*}; file=${rest##*|}
    cp "$b/$file" "$b/$file.bak"
    python3 - "$b/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    if banner_gate mut "$b" 4 131072 nvfp4 1 > "$d/banner-mut.txt" 2>&1; then
      echo "SELFTEST-FAIL the banner gate accepted [$old] changed to [$new] in $file"; rc=1
    else
      echo "SELFTEST-MUT ok banner gate stops [$old] changed to [$new]"
    fi
    mv "$b/$file.bak" "$b/$file"
  done
  # 2b. the INT4 banner opens on its own identity
  sed -i 's|Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6|Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741|' "$b/boot.log"
  printf '["tensorfold-native","serve","/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd","--no-thinking","--kv-cache","bf16"]\n' > "$b/cmd.txt"
  banner_gate good-int4 "$b" 4 131072 int4 1 > "$d/banner-int4.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the INT4 banner gate rejected the INT4 identity: $(cat "$d/banner-int4.txt")"; rc=1; }
  echo "SELFTEST-OPEN banner (INT4 identity @ 14642741)"
  # 2c. DRAFTS=0's banner says drafts off
  cp "$b/boot.log" "$b/boot.log.int4"
  sed -i 's|drafts MTP|drafts off|g' "$b/boot.log"
  banner_gate good-plain "$b" 4 131072 int4 0 > "$d/banner-plain.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the plain (DRAFTS=0) banner gate rejected 'drafts off'"; rc=1; }
  echo "SELFTEST-OPEN banner (DRAFTS=0, drafts off)"
  mv "$b/boot.log.int4" "$b/boot.log"
  # 3. the manifest gate
  mkdir -p "$d/mt/tree/zig"
  printf 'one\n' > "$d/mt/tree/zig/a.zig"
  printf 'two\n' > "$d/mt/tree/b.txt"
  python3 "$IN/mkmanifest.py" "$d/mt/tree" "$d/mt/man" > /dev/null
  python3 "$IN/verify_manifest.py" "$d/mt/man" "$d/mt/tree" > "$d/man-good.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the manifest gate rejected a matching tree"; rc=1; }
  echo "SELFTEST-OPEN manifest ($(cat "$d/man-good.txt"))"
  printf 'one changed\n' > "$d/mt/tree/zig/a.zig"
  python3 "$IN/verify_manifest.py" "$d/mt/man" "$d/mt/tree" > "$d/man-bad.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the manifest gate accepted a changed blob"; rc=1; }
  printf 'one\n' > "$d/mt/tree/zig/a.zig"; printf 'x\n' > "$d/mt/tree/extra.txt"
  python3 "$IN/verify_manifest.py" "$d/mt/man" "$d/mt/tree" > "$d/man-extra.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the manifest gate accepted an extra file"; rc=1; }
  # 4. the decode cell gate
  python3 - "$d" <<'PY'
import json, sys
d = sys.argv[1]
rows = []
for kind in ("prose", "code"):
    for p in (0, 1):
        for j in range(2):
            rows.append({"label": "T", "C": 2, "kind": kind, "pass": p, "j": j, "sha": f"x{kind}{p}{j}",
                         "prompt_sha256": f"p{kind}{p}{j}", "completion_tokens": 512, "ttft": 0.1,
                         "elapsed": 5.0, "wall": 5.0, "rate": 100.0, "rounds": 100, "drafted": 50,
                         "accepted": 40})
def dump(path, rs):
    open(path, "w", encoding="utf-8").write("\n".join(json.dumps(r) for r in rs) + "\n")
dump(f"{d}/dec-good.jsonl", rows)
dump(f"{d}/dec-short.jsonl", rows[:-1])
bad = [dict(r) for r in rows]
bad[3]["rate"] = None
dump(f"{d}/dec-norate.jsonl", bad)
PY
  python3 "$IN/check_dec.py" "$d/dec-good.jsonl" 8 > "$d/dec-good.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the decode gate rejected a full cell"; rc=1; }
  echo "SELFTEST-OPEN decode ($(head -1 "$d/dec-good.txt"))"
  python3 "$IN/check_dec.py" "$d/dec-short.jsonl" 8 > "$d/dec-short.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the decode gate accepted a short cell"; rc=1; }
  python3 "$IN/check_dec.py" "$d/dec-norate.jsonl" 8 > "$d/dec-norate.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the decode gate accepted an unmeasured row"; rc=1; }
  # 5. the exactness comparer
  cp "$d/dec-good.jsonl" "$d/dec-good2.jsonl"
  python3 "$IN/cmp_equal.py" "$d/dec-good.jsonl" "$d/dec-good2.jsonl" 2 > "$d/cmp-good.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the comparer rejected equal cells"; rc=1; }
  echo "SELFTEST-OPEN comparer ($(head -1 "$d/cmp-good.txt"))"
  python3 - "$d/dec-good.jsonl" "$d/dec-flip.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
rows[0]["sha"] = "different"
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  python3 "$IN/cmp_equal.py" "$d/dec-good.jsonl" "$d/dec-flip.jsonl" 2 > "$d/cmp-flip.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the comparer accepted a different reply sha"; rc=1; }
  python3 - "$d/dec-good.jsonl" "$d/dec-pflip.jsonl" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
rows[1]["prompt_sha256"] = "different"
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  python3 "$IN/cmp_equal.py" "$d/dec-good.jsonl" "$d/dec-pflip.jsonl" 2 > "$d/cmp-pflip.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the comparer accepted a different prompt sha"; rc=1; }
  # 6. the fidelity gate
  python3 - "$d" <<'PY'
import json, sys
d = sys.argv[1]
for name, eq in (("pass", 20), ("fail", 19)):
    json.dump({"verdict": "RESTORES" if eq == 20 else "SHAPE", "eq_QCMPB": eq, "eq_QCMPA": eq,
               "eq_I4WB": 0, "eq_I4WA": 0, "marker": eq, "gold_ok": eq, "ok": 20, "problems": [],
               "first_divergence": None}, open(f"{d}/verdict-{name}.json", "w"))
PY
  python3 "$IN/fid_gate.py" "$d/verdict-pass.json" QCMPB 20 > "$d/fid-pass.txt" 2>&1 \
    || { echo "SELFTEST-FAIL the fidelity gate rejected 20 of 20"; rc=1; }
  echo "SELFTEST-OPEN fidelity ($(head -1 "$d/fid-pass.txt"))"
  python3 "$IN/fid_gate.py" "$d/verdict-fail.json" QCMPB 20 > "$d/fid-fail.txt" 2>&1 \
    && { echo "SELFTEST-FAIL the fidelity gate accepted 19 of 20"; rc=1; }
  # 6b. arm B's internal exactness gate: its own selftest opens on a good pair and stops on each planted flip,
  # and the driver is wired to it (never to an external INT4 reference, which ran a different serve shape).
  python3 "$IN/draft_gate.py" --selftest > "$d/draft-selftest.txt" 2>&1 \
    || { echo "SELFTEST-FAIL draft_gate.py's own selftest failed: $(tail -2 "$d/draft-selftest.txt")"; rc=1; }
  grep -q '^SELFTEST ok:' "$d/draft-selftest.txt" \
    || { echo "SELFTEST-FAIL draft_gate.py did not report its selftest summary"; rc=1; }
  grep -q 'draft_gate[.]py" --base' "$SELF" \
    || { echo "SELFTEST-FAIL the driver does not call draft_gate.py for arm B"; rc=1; }
  n_fid=$(grep -c 'fid_gate[.]py" "\$d/verdict.json"' "$SELF" || true)
  [ "$n_fid" = 1 ] || { echo "SELFTEST-FAIL the driver carries $n_fid fidelity-gate invocations, want 1"; rc=1; }
  grep -q 'fid_gate[.]py" "\$d/verdict.json" QCM[P]B 20' "$SELF" \
    || { echo "SELFTEST-FAIL arm A's fidelity gate call is not the QCMPB one"; rc=1; }
  grep -q 'fid_gate[.]py" "\$d/verdict.json" "\$ref"' "$SELF" \
    && { echo "SELFTEST-FAIL the driver still gates an arm through a \$ref reference"; rc=1; }
  echo "SELFTEST-OPEN internal exactness ($(tail -1 "$d/draft-selftest.txt"))"
  # 7. qcount on 1,664 rows and on a short arm
  mkdir -p "$d/q/A" "$d/q/B"
  python3 - "$d/q" <<'PY'
import json, sys
d = sys.argv[1]
for arm in ("A", "B"):
    for bench, n in (("gsm8k", 500), ("mmlupro", 1000), ("humaneval", 164)):
        with open(f"{d}/{arm}/{bench}.jsonl", "w", encoding="utf-8") as f:
            for i in range(n):
                f.write(json.dumps({"id": f"{bench}-{i}", "text": "x", "finish_reason": "stop",
                                    "completion_tokens": 1}) + "\n")
PY
  python3 "$IN/qcount.py" "$d/q/A" > "$d/qc-good.txt" 2>&1 || { echo "SELFTEST-FAIL qcount rejected a full arm"; rc=1; }
  echo "SELFTEST-OPEN qcount ($(tail -1 "$d/qc-good.txt"))"
  head -n -1 "$d/q/A/humaneval.jsonl" > "$d/q/A/humaneval.tmp" && mv "$d/q/A/humaneval.tmp" "$d/q/A/humaneval.jsonl"
  python3 "$IN/qcount.py" "$d/q/A" > "$d/qc-short.txt" 2>&1 && { echo "SELFTEST-FAIL qcount accepted 163 HumanEval rows"; rc=1; }
  # 8. the body verifier on the real prompt files: a correct synthetic corpus passes, one body flipped fails
  python3 - "$IN" "$d/qv" "$IN/qverify.py" <<'PY'
import hashlib, importlib.util, json, os, sys
inp, out, qv = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("qverify", qv)
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
for arm in ("A", "B"):
    os.makedirs(f"{out}/{arm}", exist_ok=True)
for bench, n in (("gsm8k", 500), ("mmlupro", 1000), ("humaneval", 164)):
    items = [json.loads(line) for line in open(f"{inp}/prompts/prompts_{bench}.jsonl", encoding="utf-8")]
    assert len(items) == n
    for arm in ("A", "B"):
        with open(f"{out}/{arm}/{bench}.jsonl", "w", encoding="utf-8") as f:
            for it in items:
                f.write(json.dumps({"id": it["id"], "model": q.MODEL,
                                    "prompt_sha256": q.sha_text(it["prompt"]),
                                    "body_sha256": q.body_sha(q.MODEL, it),
                                    "error": None, "finish_reason": "stop"}) + "\n")
PY
  python3 "$IN/qverify.py" "$d/qv" > "$d/qv-good.txt" 2>&1 \
    || { echo "SELFTEST-FAIL qverify rejected a correct 1,664-body corpus: $(tail -3 "$d/qv-good.txt")"; rc=1; }
  echo "SELFTEST-OPEN qverify ($(tail -1 "$d/qv-good.txt"))"
  python3 - "$d/qv" <<'PY'
import json, sys
p = f"{sys.argv[1]}/B/gsm8k.jsonl"
rows = [json.loads(line) for line in open(p, encoding="utf-8")]
rows[0]["body_sha256"] = "0" * 64
open(p, "w", encoding="utf-8").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  python3 "$IN/qverify.py" "$d/qv" > "$d/qv-flip.txt" 2>&1 && { echo "SELFTEST-FAIL qverify accepted a flipped body sha"; rc=1; }
  # 8b. the boot-reuse gate: a boot may serve again only when the step that needs it is incomplete
  mkdir -p "$MARKS" "$OUT/SELFTEST"
  : > "$MARKS/BOOT-SELFTEST-OK"
  : > "$OUT/SELFTEST/env-diff.txt"
  BOOT_NEED=""
  boot_ok SELFTEST > /dev/null 2>&1 && { echo "SELFTEST-FAIL a boot with no data marker was reused"; rc=1; }
  : > "$MARKS/NEED-OK"
  BOOT_NEED="NEED-OK"
  boot_ok SELFTEST > /dev/null 2>&1 || { echo "SELFTEST-FAIL a complete step's boot was not reusable"; rc=1; }
  echo "SELFTEST-OPEN boot reuse (renewed when the step marker is absent, reusable when present)"
  printf 'differs\n' > "$OUT/SELFTEST/env-diff.txt"
  boot_ok SELFTEST > /dev/null 2>&1 && { echo "SELFTEST-FAIL a boot with a non-empty env diff was reused"; rc=1; }
  : > "$OUT/SELFTEST/env-diff.txt"
  BOOT_NEED=""
  rm -f "$MARKS/BOOT-SELFTEST-OK" "$MARKS/NEED-OK"
  # 8d. the raw/ preservation lands at the same path (a nested mv would re-earn 500 rows silently)
  mkdir -p "$OUT/SELFTEST/keep/raw"
  printf 'row1\nrow2\n' > "$OUT/SELFTEST/keep/raw/gsm8k.jsonl"
  : > "$OUT/SELFTEST/keep/stale.txt"
  keep_raw "$OUT/SELFTEST/keep" || { echo "SELFTEST-FAIL keep_raw returned nonzero"; rc=1; }
  [ -s "$OUT/SELFTEST/keep/raw/gsm8k.jsonl" ] \
    || { echo "SELFTEST-FAIL the preserved raw file is not at raw/gsm8k.jsonl"; rc=1; }
  [ -d "$OUT/SELFTEST/keep/raw/raw" ] && { echo "SELFTEST-FAIL the preserved raw dir nested"; rc=1; }
  [ -e "$OUT/SELFTEST/keep/stale.txt" ] && { echo "SELFTEST-FAIL keep_raw left the boot dir in place"; rc=1; }
  [ "$(wc -l < "$OUT/SELFTEST/keep/raw/gsm8k.jsonl" 2>/dev/null || echo 0)" = 2 ] \
    || { echo "SELFTEST-FAIL the preserved rows changed"; rc=1; }
  echo "SELFTEST-OPEN raw kept (same path across the boot's rm -rf, no nesting)"
  rm -rf "$OUT/SELFTEST/keep"
  # 8c. the X1 call names the flag the tool implements (resume_bench.py has --against, not --fillers)
  x1line=$(grep -F 'resume_bench.py "$URL" "$MODEL"' "$SELF" || true)
  [ -n "$x1line" ] || { echo "SELFTEST-FAIL no X1 invocation line"; rc=1; }
  case "$x1line" in *"--against 14"*) : ;; *) echo "SELFTEST-FAIL the X1 call does not pass --against 14"; rc=1 ;; esac
  case "$x1line" in *"--fillers"*) echo "SELFTEST-FAIL the X1 call passes --fillers"; rc=1 ;; esac
  grep -q -- "--fillers" "$IN/resume_bench.py" && { echo "SELFTEST-FAIL resume_bench.py still advertises --fillers"; rc=1; }
  echo "SELFTEST-OPEN X1 flag (--against, the tool's own name)"
  # 9. no local statement expands a name it declares on the same line
  local_scope_check "$SELF" || { echo "SELFTEST-FAIL a local statement expands its own name"; rc=1; }
  printf 'f() {\n  local label=$1 d=$OUT/$label rc=0\n}\n' > "$d/bad-local.sh"
  local_scope_check "$d/bad-local.sh" > /dev/null 2>&1 \
    && { echo "SELFTEST-FAIL the local-scope check passed the defect shape"; rc=1; }
  # 10. each tool parses and the quality scorer's own selftest is reported separately by the laptop
  for f in qcount.py fid_gate.py draft_gate.py check_dec.py cmp_equal.py x1_bench.py; do
    python3 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$IN/$f" \
      || { echo "SELFTEST-FAIL $f does not parse"; rc=1; }
  done
  [ "$rc" = 0 ] || { echo "SELFTEST-FAIL rc $rc"; log "SELFTEST-FAIL"; return 1; }
  echo "SELFTEST-OK env, banner (7 mutations stopped, 2 identities opened), manifest, decode, comparer, fidelity (QCMPB), internal exactness (11 flips), qcount, qverify, boot reuse, raw kept, X1 flag, local scope"
  mark SELFTEST-OK
  return 0
}

case "${1:-}" in
  window) window ;;
  preflight) mkdir -p "$OUT" "$MARKS"; preflight; rc=$?; log "PREFLIGHT-ONLY rc $rc"; echo "preflight rc $rc"; exit $rc ;;
  selftest) mkdir -p "$OUT" "$MARKS"; selftest ;;
  restore) mkdir -p "$OUT" "$MARKS"; STOPPED_PROD=1; restore; echo "restore done"; exit 0 ;;
  *) echo "usage: $0 window|preflight|selftest|restore" >&2; exit 2 ;;
esac
