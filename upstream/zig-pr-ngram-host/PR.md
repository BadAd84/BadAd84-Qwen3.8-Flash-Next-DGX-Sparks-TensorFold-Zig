# Upstream PR (not posted): patches/0012: the n-gram table's host gather on a thread gang with read-ahead

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w1-fable (`~/work/lanes/w1-fable/`, image `w1-fable-ngh`, holds m1/m2), merged image `zmerge1` (`merge/mverify.sh`, `mverify2.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0012: the n-gram table's host gather on a thread gang with read-ahead (cold prompts of new text 2-9x faster, replies byte-identical)

**Body:**

## Description and Motivation

At one GPU the engine keeps the FP8 n-gram (PLE) table host-mapped (`cuda_weights.zig` `openTable`; the
two-rank layout puts each rank's heads on the GPU) and gathers a window's rows on the engine thread, one row at a time
(`NgramTable.gather`). The table is `ple-table/`, 48.67 GiB in 34 files, and every token reads 16 rows of 160 B at
hashed offsets: 16 different 4 KiB pages. A page that is not in the page cache is a synchronous fault, and the kernel's
128 KiB read-around reads 32 pages for it: one 8k prompt of new text took the table from 2.8% to 24.9% resident (12 GiB
read for 17 MB of rows), each fault cost ~250 us on the serving thread, and the next request found its rows evicted
again. A GPU copy does not fit beside the weights on one Spark (48.67 GiB against 43.85 GiB free after load).

`patches/0012-flash-next-ngram-host-gather.patch` keeps the gather's bits (the same rows through the same LUT into the
same positions) and changes only when and on which thread the pages are read:

- `cuda_ngram_host.zig` (new): a gather of at least `TF_FLASHNEXT_NGRAM_MIN` (32) rows is split into blocks over
  `TF_FLASHNEXT_NGRAM_THREADS` worker threads plus the caller, so cold rows fault in parallel.
- `TF_FLASHNEXT_NGRAM_PREFETCH=1`: the same workers touch rows that will be gathered soon, in the background: during a
  prefill the next `TF_FLASHNEXT_NGRAM_AHEAD` (2) chunks while the current one computes; during decode the next
  window's pending token, and each draft as the MTP chain draws it.
- `TF_FLASHNEXT_NGRAM_RANDOM=1`: `MADV_RANDOM` on the table's mappings, so a miss reads its own page only.
- `scripts/config.sh` turns all three on (32 threads; 64 bought 0.1 s more at 8k on a 20-core Spark). Unset or
  `TF_FLASHNEXT_NGRAM_THREADS=0` is the engine's one-thread gather; the prefetch follows the thread count.
- The README's "the n-gram table is on the GPU" (Configuration) now says where it is at one Spark.

Why the replies do not change: the gang's blocks and the serial gather read the same rows into the same output
positions, and a touch only reads a byte of a row. Only the thread and the moment of each page read move.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). The prompt cache was off and the table's pages dropped before each cold request, with new text every time
(a repeated prompt costs no faults at all). Lane image (this patch alone on the stock engine), two cycles:

| cold prompt of new text | stock | 0012 |
| --- | ---: | ---: |
| 8k prose, s | 25.8 / 19.4 | 2.98 / 2.98 |
| 32k prose, s | 57.4 / 39.7 | 11.4 / 11.4 |
| 32k of code, s | 35.6 / 28.2 | 13.1 / 13.1 |
| 128k prose, s | 100.1 | 49.9 |
| the same 8k / 32k warm, s | 2.70 / 11.1 | 2.70-2.75 / 11.1-11.5 |
| decode, 4 clients, new text, aggregate tok/s | 100.2 / 101.9 | 128.4 / 129.7 |

A cold prompt now takes within 1-10% of a warm one (stock: 2-10x the warm time). The stock decode of new text lost
12-15% at one client and 23-24% at four (warm: 131.8 / 132.3 aggregate); with the patch it is within 1-5%. In the
merged build (with `0013` and `0017`, which do not touch prefill): cold 8k 1,167 / 1,941 -> 2,818 / 2,904 prompt
tok/s, 32k 1,741 / 2,307 -> 2,861 / 2,867, decode 1 / 2 / 4 clients equal (code 118.1 / 84.2 / 54-58 -> 117.9 / 85.1 /
59.4).

Arms dropped on the way (measured): `MADV_RANDOM` alone halves the cold cost (8k 9.58 s) but leaves the faults
serial; the gang without the prefetch is 0.4-1.3 s a cold prompt slower (8k 3.42 s).

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. Every prompt's reply sha was the same across all arms, cold and warm (8k x2 seeds, 32k x2, 32k
  code, 128k, four decode prompts, four-client sets).
- Host tests in `cuda_ngram_host.zig`: the gang's gather is the serial gather byte for byte over a three-shard table
  (1 to 4,097 rows, both shard boundaries, repeats; an id past the table fails both the same way); a draft's
  predecessors give the ids the stage computes for the next window; a chunk's touch ids from its own history equal
  the whole prompt's. Four mutants of the gang (a block skipping its last row, a predecessor off by one, the gang's
  error swallowed, a block written at the wrong offset) each fail them.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: 32 threads and a queue of row ids; the page cache holds less of the table than before, since each miss
  reads 4 KiB instead of 128 KiB.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35 and #36 merged first (logically it needs none of them). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
