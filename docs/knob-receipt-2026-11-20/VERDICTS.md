| setting | verdict |
| --- | --- |
| `TF_FLASHNEXT_CHUNK_SOLO` | **ships-as-is**: the unset default (max(chunk, 8192) at one stream) is 6.30 to 7.31 percent faster than the old explicit 3072 at 8k/32k/64k and level at 2k. 16384 is a further 1.12 to 1.39 percent at 32k/64k, so worth setting in `scripts/qwen38/zig/target/env/dev.env` only if we want that last percent (never in prod.env) |
| `TF_FLASHNEXT_READOUT_FUSED` | **worth-adopting-in-our-recipe (dev.env)**: cold TTFT faster by 3.19 percent (64k), 3.86 (32k), 4.11 (8k) and 6.47 (2k), decode level, tokens identical. That is also the data for making it the upstream default |
| `TF_FLASHNEXT_CHUNK` | **loses** (at 1536): level on decode, slower on all four TTFT cells by 6.75 to 8.15 percent; 4096 and 6144 (window 2) are level on decode and show 3 to 5 percent faster TTFT, so main's 3072 stays and our recipe needs nothing |
| `TF_CACHE_EVICT` | **level on our workload**: the resumed conversation kept its snapshot under both policies (8,598 cached tokens at A2 and A3 on both arms) and A3 TTFT was level, so the policy had no victim to choose; one decode cell flagged slower by 1.04 percent and was not rerun |
| `TF_SHARED_PRICE_LOG` | **ships-as-is**: diagnostic; every measured cell level, no token change |
| `TENSORFOLD_DEVICE_CHECK` | **ships-as-is**: startup-only; every measured cell level |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | **ships-as-is**: unset (the family default) is level with production's 10 in every measured cell; note the reserve is what bounds the window on a GB10 |
| `TENSORFOLD_UNIFIED_HOST_COUNTS` | **not-run-and-why**: explicit 0 (CUDA-pool admission) refuses to boot on this GB10: "the CUDA memory budget fits no stream ... 0.00 GiB is left after the model's 73.50 GiB and the 10.0 GiB reserve". Failed twice, 4 rejected attempts kept. The unset default (procfs) is what every other arm ran |
| `TF_FLASHNEXT_SPLIT_DENSE`, `TF_FLASHNEXT_SHARD_HEAD` | **not-run-and-why**: TP=2 pair lacks the Qwen3.8-Flash-Next checkpoint (spark5 has 72 GiB free against a 96 GiB model), no NFS export, no spark6 to spark4 key |
| the other 34 | **not-reachable**: each with its reader in `APPENDIX-reachability.md` |
