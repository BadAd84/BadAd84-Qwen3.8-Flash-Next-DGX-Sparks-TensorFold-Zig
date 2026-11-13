#!/usr/bin/env bash
# mkpatch.sh - patches/1.2.7-int4/0016 as the difference between the accepted 0001-0015 tree and the files this
# series owns in work/int4tree-Int4Port (a temp index from the worktree's own objects; nothing else is diffed).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TREE="$ROOT/work/int4tree-Int4Port"
OUT="$ROOT/patches/1.2.7-int4/0016-int4-autoround.patch"
FILES="zig/build/cuda_kernels.zig zig/kernels/cuda/fn_int4.cu zig/src/cuda/kernels.zig"
for f in cuda_batch cuda_batch_hc cuda_batch_kernels cuda_batch_side cuda_batch_state cuda_config \
  cuda_fp8_experts_load cuda_int4 cuda_int4_load cuda_mixed_experts cuda_modelopt_experts cuda_moe_native cuda_mtp \
  cuda_mtp_load cuda_ple cuda_projection cuda_projection_load cuda_prompt cuda_prompt_load cuda_prompt_step \
  cuda_prompt_wt cuda_rank_memory cuda_shared_split; do FILES="$FILES zig/src/families/flashnext/$f.zig"; done
cd "$TREE"
export GIT_INDEX_FILE="$ROOT/work/int4/mkpatch.index"
rm -f "$GIT_INDEX_FILE"
git read-tree 93a2e93ecebff8aa52b88e58c5dd222516e69c5f
for p in "$ROOT"/patches/1.2.7/00[01][0-9]-*.patch; do
  case "$(basename "$p")" in 001[6-9]-*) continue ;; esac
  git apply --cached --whitespace=nowarn "$p"
done
git add -N zig/kernels/cuda/fn_int4.cu zig/src/families/flashnext/cuda_int4.zig zig/src/families/flashnext/cuda_int4_load.zig
# shellcheck disable=SC2086
git -c core.autocrlf=false diff -- $FILES > "$OUT"
# shellcheck disable=SC2086
git -c core.autocrlf=false diff --stat -- $FILES | tail -1
rm -f "$GIT_INDEX_FILE"
( cd "$ROOT/patches/1.2.7-int4" && sha256sum 0016-int4-autoround.patch > SHA256SUMS && cat SHA256SUMS )
