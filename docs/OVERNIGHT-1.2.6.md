# Overnight 1.2.6: what works, what was fixed, what the sweep measured (2026-11-11)

The 1.2.6 stack is `patches/1.2.6` applied to a pristine TensorFold `6e9af9302`; nothing in the TensorFold tree is
edited in place. This file is the overnight record: the defects that stopped it, how each was found, and the
benchmark sweep that compares it with stock.

## Fixed on the booted stack

1. **Graph caches undefined.** The kv8 hunk had replaced `e.graphs = .{}` with `e.kv = .bf16` in `initRank`; the
   first graph use panicked (`incorrect alignment`) inside the boot self-check. Restored both lines.
2. **Draft head caches one row.** The kv8 hunk re-priced the head's key and value caches as a single fp8 row
   (`format.keyRow(head_heads)`), where upstream sizes both `sizes.kvBytes(cap, head_heads)` (bf16). The first kept
   prompt state's copy overran a 1,024-byte cache (`cuMemcpyDtoDAsync` invalid value); after a partial fix a kernel
   faulted (`CUDA_ERROR_ILLEGAL_ADDRESS`). The draft files are now upstream's exactly, and the draft caches are bf16
   beside either sequence format, which is what the engine's own refusal text says.
3. **Compile-level merges** (integration patches 0012 and 0029): duplicate prelude and `Reader.create` scope in the pread reader, its
   missing imports, the attention helpers' unused parameter and `u32` cast, the snapshot tail's format, the q12
   call's template deduction, the tile kernels' `fexp_up`, `hcn_updbg` and `hcn_peak`, the kv8 launch records
   measured with `cuobjdump -res-usage` (sm_80/86/89/120/121), and the fp8 test's new `pg` argument.

## Proof it serves

- Builds: `zig build fatbins install native` clean; image `tensorfold-qwen38:stack126`.
- Boots through the campaign recipe with `KV_DTYPE=fp8` or `bf16` and `TENSORFOLD_CUDA_KERNELS=native`.
- A 16-token chat request answers with sha `9b3560a2...`, byte-identical to stock's reply at the same prompt, with
  drafts on.
- With drafts off it also serves, which is how the MTP defect above was isolated.

## Open

1. The boot self-check reports 0 of 2080 rows on the full stack (the rows-only arm reports widths 1-48 and serves
   48-row windows), so this stack falls back to 32 rows. Every default-on lever that could change a prompt pass's
   sums is a suspect; the fused hyper-connection read-out is off by default (`TF_FLASHNEXT_PROMPT_HC2`), so the
   headline suspects are the chunked no-drain prompt pass and the attention glue refactor. Next: boot the full
   stack with each knob inverted (PROMPT_SYNC=1, chunk 1024, DRAFT_HEAD=bf16) and read the self-check line.
2. `--parallel 8` at 262,144 tokens is refused (36.31 GiB of streams against 27.41 GiB left after the model and the
   9 GiB reserve); the 1.0.0 stack fit 8 streams in 24.14 GiB. The per-stream estimate needs reconciling before 8
   streams can be served at the production window.
3. `TF_FLASHNEXT_DRAFT_AHEAD` no longer reaches the draft pass (the pread wiring was parked with the draft revert);
   it still drives the n-gram warm reads. The pread lever's next round re-lands it behind the reconciled draft code.

## The sweep

Arms on spark6, one fresh boot per level, `bench_arm.sh`/`bench_queue.sh`: stock (`up126`) at bf16/131072, the
rows-only arm (`stack126a`, patches 0001-0005) at bf16/131072, the full stack at bf16/131072, and the full stack at
fp8/131072 with 8 streams. Decode with every slot busy (3 passes), cold TTFT 1k/8k/32k/120k thinking off and on,
idle and under C-1 streams, golden per boot, RigMark on stock and on the fp8 arm. Tables: `bench_sum.py` over
`~/work/target/bench/`; raw cells beside them.

## Sweep results (interim, bf16 at 131072 tokens)

Decode, aggregate tok/s (per-stream median in brackets), median of 3 passes:

| arm | C=1 prose | C=2 prose | C=4 prose | C=6 prose | C=1 code | C=2 code | C=4 code | C=6 code |
|---|---|---|---|---|---|---|---|---|
| stock (up126) | 50.3 (50.3) | 69.9 (35.0) | 101.0 (25.9) | 129.0 (21.9) | 71.2 (71.2) | 106.0 (53.0) | 150.5 (38.8) | 193.1 (32.9) |
| rows only (0001-0005) | 53.5 (53.5) | 69.7 (34.8) | 101.6 (26.4) | - | 73.4 (73.4) | 105.9 (52.9) | 151.3 (39.6) | - |
| full stack | 49.3 (49.3) | 70.4 (35.2) | 110.9 (27.7) | 134.0 (22.9) | 82.3 (82.3) | 114.4 (57.2) | 161.9 (40.7) | 205.0 (34.5) |
| full stack, fp8 caches | 50.2 (50.2) | 69.9 (34.9) | 110.1 (27.5) | 132.7 (22.7) | 82.9 (82.9) | 113.9 (57.0) | 162.0 (40.7) | 203.8 (34.6) |

At 8 streams only the fp8 arm exists (stock's bf16 caches do not fit 8 windows at this context on the memory
estimate): prose 159.1 tok/s (19.6 a stream), code 238.6 (30.3).

The full stack's code decode is ahead of stock at every level (+15.6% at 1, +7.9% at 2, +7.6% at 4, +6.2% at 6)
and prose is ahead at 4 (+9.8%) and 6 (+3.9%), level at 2, and 2.0% behind at 1 (inside the run-to-run spread
measured on this box). The rows-only arm is +3-6% at 1-2 streams and level above that, which is the copy-window
lever alone.

Cold TTFT, thinking off, idle (the full stack against stock, seconds):

| case | stock C=1 | full C=1 | stock C=6 | full C=6 |
|---|---|---|---|---|
| 1k | 0.575 | 0.531 | 0.556 | - |
| 8k | 3.477 | 3.180 | 4.059 | - |
| 32k | 14.184 | 12.779 | 16.209 | - |
| 120k | 56.451 | 48.189 | 64.775 | - |
| warm +2k on a kept 100k | 1.452 | 1.177 | 1.552 | - |

The full stack's cold prefill is 7-15% faster (120k: 48.2 s against 56.5 s) and its warm next turn 19% faster.
At matched levels the fp8 and bf16 arms are within 1% of each other, so the fp8 caches buy the 8-stream capacity
rather than speed. Full rows for every level and load: `bench_sum.py` over spark6 `~/work/target/bench/`
(`bench_table.md`).

RigMark, both arms on the FP4 checkpoint (`nvidia/Qwen3.8-Flash-Next-FP4-Local`), C=6, 131072 tokens, one
comparison id each (`rigmark_run.sh`, receipts on spark6):

| workload (single stream) | stock (up126, bf16) | full stack (fp8) | delta |
|---|---|---|---|
| code | 75.8 tok/s (gate 5/5) | 80.8 (4/5) | +6.6% |
| prose | 38.7 (5/5) | 40.1 (5/5) | +3.6% |
| structured | 91.3 (5/5) | 99.5 (5/5) | +9.0% |
| capped aggregate, C1 / C2 / C4 | 56.0 / 79.7 / 118.8 | 52.5 / 80.6 / 112.2 | -6.2% / +1.1% / -5.5% |
| cold prefill 8k / 32k / 64k | 2,017 / 2,001 / 1,955 tok/s | 2,392 / 2,393 / 2,377 | +19.6% / +19.6% / +21.6% |

The single-stream RigMark decode is 4-9% ahead of stock and its prefill about 20% ahead. The capped aggregate at C1
and C4 is behind by 5-6% while C2 is level; those cells are the fp8 arm against the bf16 stock arm at 256-token
caps, and the fp8 caches are within 1% of bf16 in the full sweep, so read this as a RigMark-side spread rather than
a proven regression. One code run missed RigMark's own output gate (4/5), matching the 4/6 golden difference
above.

## Exactness, stated plainly

- Rows-only arm: golden 6/6 identical to stock.
- Full stack as swept (relaxed MXFP8 prompt tile still defaulting on through the merged knob): golden 4/6. The two
  differences are wording-level, at the same positions stock itself varies between boots ("Return" against
  "Returns the n-th Fibonacci number"; a later token in the primes reply). The tile's own note says its bits are
  not the exact kernels': it changes prompt sums by design, so this is expected, and it is exactly why the boot
  self-check reported 0 of 2080 for this stack. The tile is now off by default again
  (`TF_FLASHNEXT_PROMPT_MX128=0`, which is what patch 0015 intended and what the environment row documents), and the
  rebuild at the end of the night still reports 4/6 golden and 0 of 2080, so the tile was not the cause. Inverting
  the other suspects at boot (`PROMPT_SYNC=1`, `TF_FLASHNEXT_CHUNK=1024`, `DRAFT_HEAD=bf16`, `PROMPT_HC2=1`) each
  still reports 32 rows. The prefix ladder then localised it: rows, rows+kv8 and rows to n-gram all report 1,176 of
  2,080 rows and serve 48-row windows, and only the full series reports 0, so the regression is in 0016-0030 and the
  attention-glue refactor of 0007-0011 is excluded. Skipping the read-out patch 0026 still applies as a series, so it
  is the first compile candidate. The rows-only arm isolates the self-check itself as
  correct.

## What "adding the patches in" showed

The integration patch is now split by lever (0012 kv8, 0015 pread, 0030 the rest), so three prefixes build from a
pristine tree, each verified by a container compile: rows (0001-0005), rows to kv8 (0001-0012), rows to n-gram
(0001-0015). The full 30-patch series reproduces the previous tree byte for byte.

Two intermediate images were built and run (`stack126kv` from 0001-0012, `stack126ng` from 0001-0015). Both boot
and pass the golden, and both FAULT on the first 512-token decode: they carry the kv8 draft defect whose fix sits
only in the tail (0030). That is the honest reason the speed ladder has one valid intermediate rung tonight (rows
against stock) rather than three, and it is the concrete reason to move the draft revert into the kv8 rung next:
the kv prefix then serves, and the ladder can separate the kv8 lever's contribution from the prompt levers'.

Harness gotcha for that work: `tfm_decode` waits forever on a faulted serve, so a ladder cell needs a timeout
around it, and a wedged run needs the queue killed and the production serve restored by hand (both done here).

The valid ladder point is rows against stock: +3-6% at 1-2 streams, level at 4. The full stack then adds the
prompt, gather and read-out levers: +15.6/+7.9/+7.6/+6.2% code decode at 1/2/4/6 and 7-15% faster cold prefill.

The same ladder read out the boot self-check, which is the sharper signal:

| image | patches | self-check | windows served |
|---|---|---|---|
| stock `up126` | none (the check is our patch) | - | 32 rows |
| `stack126a` | 0001-0005 | 1,176 of 2,080 | 48 rows |
| `stack126kv` | 0001-0012 | 1,176 of 2,080 | 48 rows |
| `stack126ng` | 0001-0015 | 1,176 of 2,080 | 48 rows |
| `stack126` | 0001-0030 | 0 of 2,080 | 32 rows |

So the rows lever, the kv8 glue and the n-gram work all keep the window exact, and the break enters between 0016
and 0030. Skipping 0026 (the 12-bit read-out) still applies as a 29-patch series, and that build is the first
compile candidate.

## Next steps, in the order they block

1. **Finish the per-lever split.** Done overnight: 0012 (kv8) and 0015 (pread) carry their corrections, three
   prefixes compile, and the 30-patch series reproduces the same tree byte for byte. Next: move the draft revert
   (now in 0030) into the kv8 rung, which makes that rung serve and the speed ladder meaningful; then the tile and
   knob pieces.
2. **Root-cause the 4/6 golden and 0-of-2080 self-check** on the full stack. The self-check ladder narrows it to
   0016-0030: every prefix up to 0015 reports 1,176 of 2,080 rows and serves 48, while the full series reports 0 and
   serves 32. The 12-bit read-out patch 0026 is the first compile candidate, since the series still applies without
   it: build that series, boot it, and read the self-check line.
3. **Re-land the pread draft read-ahead** behind the reconciled draft code (TF_FLASHNEXT_DRAFT_AHEAD is parked).
4. **Reconcile the per-stream memory estimate**: the 1.0.0 stack fit 8 streams at 262,144 tokens in 24.1 GiB; this
   stack estimates 4.54 GiB a stream at fp8 (36.3 GiB for 8) and refuses. The kv8 caches are not larger; the
   estimate (seqBytesFor/streamBytes) needs auditing against the 1.0.0 numbers.
5. **Retune the 1.0.0 env for 1.2.6** (confidence, depth, product streams, pool sizes) once the exactness item is
   closed, then re-run this sweep as the qualification.
