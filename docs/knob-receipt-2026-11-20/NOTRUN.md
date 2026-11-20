# Cells and knobs not taken, with the reason

## The two-rank knobs: `TF_FLASHNEXT_SPLIT_DENSE`, `TF_FLASHNEXT_SHARD_HEAD` are NOT RUN

They are layout knobs of the Flash Next two-rank path. `cuda_dense_split.zig`'s `applies()` returns false when
`world != 2` and `cuda_head.zig`'s `shard()` refuses `world != 2`, so at TP=1 they are read only for their value and
change nothing. The TP=2 pair boxes were idle and permitted (checked 2026-11-20 13:52 UTC: no `flock` holder, no
container, GPU 0 percent at 41 and 38 C on spark4 and spark5), so idleness was not the obstacle:

- neither spark4 nor spark5 holds the checkpoint the family serves: `~/.cache/huggingface/hub` has
  `models--deepseek-ai--DeepSeek-V4.1-Flash-1017` and the Mia-AI-Lab EXL3 of it, and NO
  `models--nvidia--Qwen3.8-Flash-Next-FP4-Local`;
- the checkpoint is 96 GiB (`scripts/config.sh`: `CKPT_GIB=96`) and spark5 had 72 GiB free on `/home` (92 percent
  used), so it does not fit even before the ~25 GiB runtime image; spark4 had 116 GiB;
- spark6 does not export its cache over NFS (`/etc/exports` holds only the commented example) and no pair box has an
  NFS or 9p mount of it, so a shared read is not available either;
- spark6 cannot ssh to spark4 (`Permission denied (publickey,password)`), so an image transfer needs a key first.

What WOULD take them: a 96 GiB download onto spark4 and spark5 (or an NFS export of spark6's cache and a key), then
the documented two-rank start (`tensorfold-native serve <ckpt> --tp 2 --rank N --master <spark4>` with
`--prompt-cache-gib 0`, `NCCL_SOCKET_IFNAME` and `NCCL_IB_HCA`), one arm at `SPLIT_DENSE=1` (its default) and one at
`0`, one at `SHARD_HEAD=0` (its default) and one at `1`, decode at 1, 2 and 4 streams with token equality against
the default. The pair has never served this family in this repo, so the first boot would also have to prove the
TP=2 path itself.

## Cells not taken inside the windows that DID run

- The cold TTFT cells are `--loads idle` only. `ttft.py`'s `load3` (three other streams decoding) is not run: the
  decode table already gives the beside-decoders picture through `bench_concurrent` at 2, 4, 6 and 8 streams, and a
  `load3` pass would add about 2.5 minutes a boot to every prompt-touching arm.
- The pass A exactness probes use `--tokens 128 --reps 2` for the sampled (temperature 1.0) cells and the greedy
  cells of the decode pass for temperature 0; a longer sampled run is not taken.
- `TF_CACHE_EVICT`'s resume cell is one 9,000-token conversation under 14 fillers then 10 more (`resume_bench.py`),
  not a replay of a real agent trace; the policy's own receipt (#3258) measured agent traces, this receipt measures
  whether the policy changes a resume in OUR budget.
