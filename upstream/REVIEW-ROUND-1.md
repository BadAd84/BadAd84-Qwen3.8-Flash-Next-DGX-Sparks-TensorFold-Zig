# Review round 1: replies to the maintainer's notes on #34-#36, #42-#50, #53-#57

Internal header (not posted). Engine side: the stack 0010-0024 rebuilt as one commit per patch (image
`tensorfold-qwen38:zpr-r1e-stack`, built from exactly the patches inside the new `pr.diff`s). Every prefix of the
stack passes `zig build test` with only the patches before it (0010: 180 tests ... 0024: 202). Packages:
`upstream/zig-pr-*/pr.diff` and `mutants.sh` regenerated (`gen_r1.py` + `review1.py`), with `review-round-1.diff`
beside each (new against posted, both applied to main 364f21a). Host mutants (`hostmut.py`): 16 of 16 KILLED. GPU
mutants, all on zpr-r1e-stack, every mutant build (and the control) rebuilt from the r1e source (tf `stack` 5634f04,
tree-identical to the recipe patches plus the fifteen r1e `.patch` files; `gmutbuild.py`, `gmutbuild4.out` for the
pool-check and boot mutants, `gmutbuild5.out` for the rest), verdicts
by exit code (`gpucheck.sh`: the control build must pass, each mutant must fail): window-check (control 0;
fp8-rows-past-16-half-slices exit 1, windows of 41+ rows differ from their one-row steps), fill-check (control 0;
fill-free-keeps-pfill exit 1), int4-head-check (control 0; int4-dense-no-tail-mask exit 1, bytes past the call's rows
written), hc-check (control 0, 675 cases and 12 allocation-failure runs clean; table-add-append-then-put exit 1, a host
allocation failure frees a buffer twice; table-add-free-then-alloc exit 1, two device allocation failures free a buffer
twice), qsa-check (control 0; qsa-stream-minus-zero-is-zero and qsa-stream-nan-is-zero exit 1), pool-check
(reset-keeps-recurrent-state exit 1), boot (reduce-act-one-off: the difference reported, golden still 6/6, exit 1), and
`argmaxmut.sh stack` (clean exit 0; tree-quarter exit 1, lse max 29.9995 vs 29.9998; tree-drops-nan exit 1, 30 vs nan):
11 of 11 KILLED on r1e (`runs/mut-r1eclose.log`, `runs/mut-r1emut.log`). The engine checks (13 verdicts) all exit 0 on
zpr-r1e-stack, glue-check included. Leak scan over every `pr.diff`, `review-round-1.diff` and this file: clean. Each
section's last sentence is the common blocker's short form; the full note is the paragraph below.

Memory attribution (internal). The first r1e arm's serving low-water (29.21 GiB, 11:31-11:40) ran while host-side
`zig build test` jobs shared the box: `hostmut.py` (the clean tree and 16 mutants, 11:31:10-11:37:41) and `each-env.sh` (every
prefix, 11:37:41-11:43:10, so through the whole FILL=0 phase where the low fell). One such build alone (fresh cache,
`zmem.sh`) takes MemAvailable from 40.86 to 38.85 GiB (2.01 GiB; other processes' RSS up to 3.13 GiB), which matches
the 2.4-2.6 GiB gap. Re-run on a quiet box, interleaved posted, r1e, r1e, posted with the same probes, the 1 s sampler
and a sidecar (meminfo detail, every process's RSS, compiler count 0 throughout; nvidia-smi per process in the later
boot-only arms): serving
low-water posted 31.27 / 31.60, r1e 31.58 / 31.67 GiB; in all four, 38/38 sampled and 5/5 prefill replies identical to
stock and 14/14 FILL=0 replies identical to the posted stack's first run. The engine's GPU memory once loaded (after
golden) is 74,206 MiB (vision helper 1,199 MiB) in every default boot read with nvidia-smi, both stacks (3 posted, 4
r1e), so no r1 fix allocates more. The sizing figure (MemAvailable when the engine sizes the
sequence memory) spreads 42.91-43.47 GiB over 5 posted boots and 42.27-43.39 over 7 r1e boots (means 43.11 and 42.96)
with that same GPU memory, anon, page cache and slab: run-to-run noise outside the engine, so no env bisect was
needed. The variant arms of #43/#54/#57 were re-measured on r1e twice each (`runs/mv-*`); their GPU deltas replace the
posted-stack MemAvailable deltas, which were within this noise.

Common blocker (every PR): The recipe has no files named `bench_draft` or `exact_prefill` (not in main, in its
history, or in TensorFold's branches); the only mention we found is the sampling note in #4. So we ran the recipe's
own `tools/exact.py`, `tools/exact.py --pad 3k`, `tools/toolcheck.py` and `tools/needle.py`, plus two probes standing
in for the two names: a "bench_draft" probe (recipe sampling: temperature 1.0, top_p 0.95, top_k 20, seed 1234; 38
replies compared by text sha, token sha and finish reason) and an "exact_prefill" probe (cold greedy prompts of about
8k, 32k and 120,312 tokens, 32k with `"draft": false`, and a 32k cache resume). Each arm runs the recipe's `start.sh`
at its defaults (8 x 262,144, fp8 KV, vision on) on one GB10. Stock 1.0.0 and the posted stack: golden 6/6 both;
`exact.py` PASS both (482 and 527 drafts accepted); `--pad 3k` PASS both; toolcheck 3/3 both; needle found at 199,730
tokens both (prefill 101.00 s stock, 73.84 s stack); the bench_draft probe 38/38 replies identical to stock; the
prefill probe 5/5 identical. The fixed stack (this round): golden 6/6; `exact.py` PASS (527 drafts accepted) and `--pad 3k` PASS (522); toolcheck 3/3; needle found at 199,730 tokens (prefill 74.84 s); the bench_draft probe 38/38 replies identical to stock, drafted == `"draft": false` == concurrent for 11/11 prompts (1,479 drafts accepted); the prefill probe 5/5 identical; 14/14 replies of the FILL=0 concurrency probe identical. With `TF_FLASHNEXT_QSA_SELECT=0`: golden 6/6, `exact.py` PASS, 38/38 sampled and 5/5 prefill replies identical to stock. If you have the `bench_draft` /
`exact_prefill` scripts you meant, please share them and we will run them as well. Merge order: the patches merge in
number order (see #47).

## #34 config: TF_FLASHNEXT_CONFIDENCE=-0.15 on one Spark

Batch note (the GPU exactness run for every PR in this batch). The recipe has no files named `bench_draft` or `exact_prefill` (not in main, in its
history, or in TensorFold's branches); the only mention we found is the sampling note in #4. So we ran the recipe's
own `tools/exact.py`, `tools/exact.py --pad 3k`, `tools/toolcheck.py` and `tools/needle.py`, plus two probes standing
in for the two names: a "bench_draft" probe (recipe sampling: temperature 1.0, top_p 0.95, top_k 20, seed 1234; 38
replies compared by text sha, token sha and finish reason) and an "exact_prefill" probe (cold greedy prompts of about
8k, 32k and 120,312 tokens, 32k with `"draft": false`, and a 32k cache resume). Each arm runs the recipe's `start.sh`
at its defaults (8 x 262,144, fp8 KV, vision on) on one GB10. Stock 1.0.0 and the posted stack: golden 6/6 both;
`exact.py` PASS both (482 and 527 drafts accepted); `--pad 3k` PASS both; toolcheck 3/3 both; needle found at 199,730
tokens both (prefill 101.00 s stock, 73.84 s stack); the bench_draft probe 38/38 replies identical to stock; the
prefill probe 5/5 identical. The fixed stack (this round): golden 6/6; `exact.py` PASS (527 drafts accepted) and `--pad 3k` PASS (522); toolcheck 3/3; needle found at 199,730 tokens (prefill 74.84 s); the bench_draft probe 38/38 replies identical to stock, drafted == `"draft": false` == concurrent for 11/11 prompts (1,479 drafts accepted); the prefill probe 5/5 identical; 14/14 replies of the FILL=0 concurrency probe identical. With `TF_FLASHNEXT_QSA_SELECT=0`: golden 6/6, `exact.py` PASS, 38/38 sampled and 5/5 prefill replies identical to stock. If you have the `bench_draft` /
`exact_prefill` scripts you meant, please share them and we will run them as well. Merge order: the patches merge in
number order (see #47).

Range checking, measured. We ran the engine's own `confidenceSetting()` (TensorFold at the recipe's pin, with the
recipe's patches) on 16 values. `-0.15`, `0.5`, `0`, `-1` and `1` are read as given. Unset, `1.0001`, `-2`, `abc`,
empty, `nan`, `inf`, `-inf`, ` -0.15` (leading space), `-0.15x` and `1e300` all fall back to the engine default
`-0.4`. So the engine only takes finite numbers in -1..1 and never acts on a malformed value. No diff change.
GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #35 patches/0010: argmax and logsumexp row maxima on 1024 threads

The 1024-thread reduction is now tested on the GPU. The new `zig/tests/cuda/flashnext/argmax_lse_rows.cu` (nvcc
command in its header) runs `tf_fn_lse_max_kernel` and `tf_argmax_rows_i32_kernel` at every power-of-two block from 32
to 1024 threads. It requires the same bits at every block size and a match with a host reference. Its rows put the
maximum, or the only NaN, at column 1023 or 511 (the last thread of a 1024 or 512 block, so the tree's last steps must
carry it), plus ties, the 4-wide loop's remainder, +-inf, -0/+0, and widths 1 to 248,320. On the GPU: "PASS
argmax_lse_rows: 144 rows at 6 block sizes (32-1024 threads), 0 differences". Two mutants of the block tree each make
it fail: the tree starting at blockDim/4 ("lse max differs from the host: width 248320 row 0") and the right-hand NaN
arm dropped ("width 248320 row 6: 30 vs nan"). GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #36 patches/0011 + MTP_FP8: the MTP draft layer on block FP8

Fixed as suggested: the overlay is now keyed by content and by tool version. `mtp_fp8_sub` is
`<revision>/tool-<first 12 hex of sha256(tools/mtp_fp8.py)>`, so a changed tool writes a new overlay. `mtp_fp8.py`
writes `mtp-fp8.sha256` beside the overlay (removing the old checksum first, so a half-written overlay has none). The
new `mtp_fp8_ok` (`sha256sum -c`) decides in `prepare.sh` (rewrite, then verify or stop), in `start.sh` (warn and
draft from bf16) and in `prepared_state`. Test (`t36.sh`, through the recipe's own config.sh on the pinned
checkpoint): the tool's output is accepted; one byte flipped is refused; the tool edited is refused; the checksum
removed is refused; each case is also checked through `prepared_state`. PASS. Mutants: `mtp_fp8_ok` without the
checksum, and the directory without the tool hash: both KILLED (t36 exits 1). README and CHANGELOG updated.
GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #42 patches/0012: the n-gram table's host gather on a thread gang with read-ahead

`TF_FLASHNEXT_NGRAM_AHEAD` is capped at 16 and `TF_FLASHNEXT_NGRAM_THREADS` at 128. A value past its cap, or one that
is not a number, stops the start with the setting named (it is never read as the default). The host test "the
settings are refused past their caps" also proves `(16 + 1) * 16384` cannot overflow; its mutant (no cap) is KILLED.
Re-measured on the fixed stack with it on by default, at 8 x 262,144 with vision, in four arms interleaved with the
posted stack (posted, fixed, fixed, posted; the same probes; MemAvailable sampled every second): start.sh found 118 GiB
available against the ~94 GiB it needs; the engine reports 31.04 and 30.27 GiB of sequence memory (43.04 and 42.27 GiB
free when it sizes it; posted 43.47 and 43.06); the page cache stays flat at 26.0 GiB while serving (on stock it grows
from 21.7 to 32 GiB); and MemAvailable's low-water mark over the 200k needle, the 120k prompt and 14 concurrent
requests was 31.58 and 31.67 GiB (posted 31.27 and 31.60, stock 31.37), more than 21 GiB above the 10 GiB reserve.
Once loaded, the engine holds 74,206 MiB of GPU memory (nvidia-smi) in every boot we read, posted and fixed alike, and
the same 74,206 MiB with the gang off (`TF_FLASHNEXT_NGRAM_THREADS=0`); the free figure at sizing moves by up to
1.2 GiB from boot to boot with that same footprint (42.27-43.47 GiB over 12 boots of both stacks). GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #43 patches/0013: 64-row copy windows for a lone stream

Row invariance at 17-64 rows now has a test: `tensorfold window-check MODEL --tokens-file P` (run with
`TF_FLASHNEXT_WINDOW=64`) requires every row of a 1-64 row window to give the same logits bytes as its one-row step. On
the GPU: "PASS window-check: windows of 1-64 rows, 2080 rows, 0 differ from the one-row steps". A mutant that splits
the block-FP8 matmul's K differently past 16 rows fails it (exit 1). Memory at 8 x 262,144 with vision, on the fixed
stack: once loaded, the engine holds 74,206 MiB of GPU memory (nvidia-smi) with window 64 and the same 74,206 MiB with
window 16 (the window-16 boot we read), so the 64-row windows add no measurable memory at the recipe's settings. The
free figure at sizing was
42.66 and 42.53 GiB in two boots with window 16 against 42.27-43.39 GiB in seven with window 64, which is the
boot-to-boot spread at an identical footprint (see #42). The start passes, and MemAvailable stayed at or above
31.58 GiB while serving.
GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #44 patches/0014: copy re-sync after an edit and a wider copy ramp

The `min_match` change is measured, not argued. The host test "raising min_match to the round loop's enter_match"
feeds proposers with min_match 4 and 8 through the round loop (gate `enter_match` 8). Their proposals are identical
until the first difference, and that difference is always a re-sync by the min_match-8 proposer where the other's 4-7
token match was dropped by the gate anyway; without re-sync there is no difference. So the only behaviour change for a
lone stream is the re-syncs it lets through, and replies stay verified. Mutant (min_match not raised): KILLED.
GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #45 patches/0015: copies out of the prompt ramp in shared rounds too

Fixed: every proposal clears `SuffixLookup.last_out`, so `lastFrom()` is null after a proposal that returned nothing
(the vtable doc is updated). Host test "lastFrom answers for the latest proposal only"; mutant (not cleared): KILLED.
On the order: it needs 0013 and 0014 first, and all patches merge in number order (see #47). GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #46 patches/0016: pooled sequences keep their CUDA graphs across requests

Reset completeness is now a test. A host gate classifies every field of `Seq` and `State` and requires each reset
statement to be found in `recycle` or in `Forward.reset` (`Seq.media`, `st.history` and the MTP state included; the
recycle doc lists everything cleared). Each part of the fixed state (DeltaNet conv and recurrent state, PLE tail, the
device position, rope delta and MTP length) is tied to the `Forward.reset` statement that resets it. Mutants: the MTP
drafts not reset, and the recurrent state not reset: both KILLED. The GPU check `tensorfold pool-check`
(`TF_FLASHNEXT_SEQ_POOL=1`) runs a drafted request with an image attachment, then requires the pooled sequence to
equal a fresh one in 18 host fields, the fixed-state bytes, the 52 zeroed cache regions and the next 256-token reply:
"0 differ". On the fixed stack it passes, and a mutant whose `Forward.reset` keeps the DeltaNet recurrent state makes it fail (exit 1; the same mutant also fails the host gate). (While testing we found that recycle's extra zero of the whole fixed arena repeated what
`Forward.reset` already does, which is why a mutant dropping it survived; that zero is gone.) Settings: `SEQ_POOL`,
`WARM_POOL`, `MULTI_VERIFY`, `MULTI_MAX` and `SOLO_MAX` go through one strict reader (`envCount`) that refuses a value
that is not a count. `SEQ_POOL` above 0 at two GPUs, or `WARM_POOL` at tp != 1, stops the start. Host test "count
settings ..."; mutant (a bad value read as unset): KILLED. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #47 patches/0017: one launch and one read for a draft level's greedy draws

Merge order: the patches are one stack and merge in number order, 0010 first, then 0011, 0012, ... 0024 (this one
after 0016), with the two config PRs (#34, #57) at any point. Each patch's context is the tree with every
lower-numbered patch applied. We built and ran `zig build test` on every prefix of the stack, from 0010 alone to
0010-0024, and each passes with only the patches before it (this PR's prefix: 193 of 193 tests). If one is merged out
of order, we rebase the rest. This patch has no code change in this round; only its context moved with the earlier
fixes. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #48 patches/0018: fused split-K block-FP8 projections and 32-row lm_head items

The GPU checks now verify tails and bounds themselves: `fp8-fused-check` and `int4-head-check` compare the whole
poisoned output buffer, so a write past the tail rows or into the row gaps fails. Both PASS on the GPU; a mutant with
no tail mask in the 32-row item fails `int4-head-check` (exit 1). `TF_FLASHNEXT_HEAD_ROW_TILES` must be 1 or 2, and
anything else stops the start; host test "the head's row tiles setting is 1 or 2", mutant (silently 1) KILLED.
`FP8_FUSED_SPLIT` must be 0, 4 or 8, and `FUSED_SPLIT_N` a count, read through the same strict reader as in #46.
GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #49 patches/0019: decode read-outs fused, up projection + mix and reduce + activation

Fragility across Triton/ptxas versions: the engine now checks at every start (`reduceActAgrees`) that the fused kernel
gives the loaded kernel set's bytes; on a difference it keeps the two original launches and says so. On the stack
image: "decode read-outs: _reduce and _hc_act in one launch (tf_fn_hc_reduce_act_kernel, checked against the kernel
set at load)", golden 6/6. A mutant kernel whose activation adds 2^-8 to the 1 + exp(-v) is caught at load: "warning: decode read-outs: tf_fn_hc_reduce_act_kernel differs from this kernel set's _reduce + _hc_act; the two launches ..." and "hc q12 off", and golden stays 6/6 on the two launches. `glue-check` covers the kernel itself: "EQUAL hc_reduce_act: 134 cases",
"PASS reduce-act-check", 112 EQUAL `_hc_up_mix`. (Its last part, the release's own write-back + norm check, stops on
a `_hc_writeback` variant the kernel set lacks, on stock 1.0.0 too; it now prints a SKIP line for that part instead of
failing the whole check.) We also measured how far the hand-written exp can drift: the activation's input is a bf16
value, and over all 65,536 of them, `expf` in place of the ex2.approx sequence, or an input one ulp off, gives the same
act and gate bits. `f.sc.part`: the scratch now records its size, and the fused path falls back when the split needs
more. Host test "the partial scratch covers the widest split-K matmul" (every row count of the 324 x 10240 split);
mutant (scratch halved) KILLED. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #50 patches/0020: split draft stop lines, the int4 lm_head as draft head, depth 7 at 2+ streams

`TF_FLASHNEXT_DRAFT_INT4=1` without an int4 head now warns and drafts from the 4-bit draft rows. `draft_head` is never
a Q4 with null pointers (`Weights.draftColumns()` is the one reader), and the draft ids pad to 8-column tiles only for
the int4 head: host test "the draft ids pad to whole 8-column tiles only", mutant KILLED. `_PROPOSE` and `_CONTINUE`
are set together, as numbers with 0 < propose <= continue <= 1, or the start stops: host test "the split stop lines are
both or neither", mutant (one setting silently ignored) KILLED. Sampled replies: all 38 sampled replies (thinking off
and on, drafted, `"draft": false`, 8 concurrent) are byte-identical between stock and the stack, and within each
image drafted == `"draft": false` == concurrent for all 11 prompts (1,479 drafts accepted). This holds by
construction too: each token is a keyed Gumbel-max draw on (seed, position, token id), and a draft is accepted only
when it equals the target's own keyed pick, so drafting cannot change a sampled reply while the logits are
bit-identical. The fixed stack gives the same: 38/38 sampled replies identical to stock, 11/11 prompts drafted == serial == concurrent. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #53 patches/0021: fix TF_FLASHNEXT_FILL=1 with two or more prompts at once

Checked on the real engine with `tensorfold fill-check`: fill A holds `pfill`; a resumed fill B defers its absorb and
gets `PromptBuffersBusy`; cancelling A with `fillFree` clears `pfill`; B's reply and A's refilled reply must equal a
fresh prefill's. On the GPU: "1013-token prompt resumed at 506, 256-token replies, 0 failed"; the mutant where
`fillFree` keeps `pfill` fails it (exit 1). Cancel path: a client that leaves is seen between rounds -> `endFill`
-> `releaseFn` -> `stopFill` -> `Engine.fillFree`, which clears `pfill` when it was this fill's. `seq.last_streams`
after a restore: `newSeq` allocates it for every sequence before it returns (an allocation failure fails `newSeq`),
and it is kept for the sequence's life and freed only with it, so the unwrap in the resume path cannot meet null;
fill-check's fill B is exactly that resume. The bug on the release, for reference: stock 1.0.0 with `FILL=1` fails all
four simultaneous prompts with "HTTP 500: PromptBuffersBusy". With `TF_FLASHNEXT_FILL=1` on the fixed stack, the 14 replies of the concurrency probe (prompts starting together, resumes) are identical to stock's at FILL=0, and golden is 6/6. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #54 patches/0022: decode read-outs from a lossless 12-bit copy of their weights

One predicate, `q12DownTakes` (K slices of 320, at most 32; streams a power of two; x % 16; `x_stride % 8`; at most 64
column groups for the counters), decides both `hcDownQ12` (error) and `Forward.q12Down` (fallback), which also checks
the partial scratch. Host test "q12DownTakes ..."; mutants (stride unchecked, counters unchecked) KILLED. `Table.add`
reserves room in the list and the map before allocating, and allocates the larger counts buffer before freeing the
old one. `hc-check` gains an allocation-failure pass (every host and device allocation failed in turn; a double or
missing free fails): "EQUAL hc q12: 675 cases", "EQUAL hc q12 table allocation failures: 12 runs, 0 wrong"; the
mutants append-then-put and free-then-alloc each fail it (exit 1). `HC_Q12` now builds the copies only where the fused
read-out tail matched the kernel set (#49's check); mutant KILLED. Memory: the copy is 970.8 MB (1266.2 MB of bf16
weights, 95,876 escapes) and the start's memory check now counts it (+1 GiB in `config.sh` when `TF_FLASHNEXT_HC_Q12`
is on: start.sh's estimate reads ~94 GiB with it, ~93 without, and passes). Measured on the fixed stack at 8 x 262,144 with vision: once loaded, the engine holds 74,206 MiB of GPU memory (nvidia-smi) with the copies and 73,287 MiB with `TF_FLASHNEXT_HC_Q12=0`, so the copies take 919 MiB (964 MB; the copy's own size is 970.8 MB); the free figure at sizing was 44.25 and 44.17 GiB without them against 42.27-43.39 GiB (mean 42.96) over seven boots with them. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #55 patches/0023: the sparse-attention indexer's block lists from one read of each row

`QSA_SELECT=0` now makes the original calls verbatim (`qsaSelectRope` in the decode path, `qsaRows` in `qsaDecode`,
with or without profiling). The host test "QSA_SELECT=0: the decode indexer's launches ..." records the launches and
compares them with the original calls; mutant KILLED. (The posted split already launched the same kernels; only the
profiler marks differed.) With `QSA_SELECT=0`: golden 6/6, `exact.py` PASS, and the sampled (38/38) and prefill (5/5) replies identical to stock 1.0.0. NaN/inf ordering: `qsa-check` gains a direct-scores pass
(NaN of both signs and several payloads, +-inf, +-0, ties, mixes) through `_select_tiles` and each select kind,
compared with Python's choice: 24 EQUAL at positions 131,000 / 200,000 / 261,000, rows 1, 3 and 16. Mutants that read
-0 as +0, or NaN as 0, each fail it (exit 1). GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #56 patches/0024: larger block-FP8 prompt tiles and the int4 prompt kernel for the experts' gate/up

The shared memory is checked, not assumed: a compile-time assert keeps `promptGuSmem <= 101376`, and at load the kernel
runs only if its dynamic plus static shared memory fits the device's opt-in limit (otherwise `int4_kernel`).
`gateUpPromptFits` (width a multiple of the block's 128 columns, K groups of 128, alignment) makes `promptGu` fall back
to `int4_kernel` instead of returning an error. Host test "the prompt gate/up fits sm_121's shared memory, and takes
widths of whole column blocks"; mutants (shared memory unchecked, width unchecked) KILLED. `int4-check` and
`fp8-tiles-check` PASS on the GPU. GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).

## #57 config: TF_FLASHNEXT_PREFILL_ROWS=4096 on one Spark

Re-run on the fixed stack at 8 x 262,144 with vision on, two boots with 2048 rows beside seven with 4096: once loaded,
the engine holds 74,206 MiB of GPU memory (nvidia-smi) with 4096 rows and 72,915 MiB with 2048 rows, so the larger
chunk takes 1,291 MiB (1.26 GiB). The free figure at sizing was 44.22 and 44.05 GiB with 2048 rows (sequence memory
32.22 and 32.05 GiB) against 42.27-43.39 GiB with 4096 rows (sequence memory 30.27-31.39 GiB). MemAvailable's
low-water mark while loading is 39.48-40.59 GiB with 4096 rows (41.34 and 41.21 GiB with 2048 rows). While serving,
with 2048 rows it stayed at or above 33.95 and 32.79 GiB over the prefill probe (prompts up to 120,312 tokens) and the
199,730-token needle; with 4096 rows at or above 31.58 and 31.67 GiB over the whole default arm (the needle, the
prefill probe and 14 concurrent requests among the others; 32.86 and 32.87 GiB over its prefill probe). start.sh's
estimate (~94 GiB) passes in every arm, and the 10 GiB reserve was never approached. With 2048 rows the prefill
probe's replies are identical to those with 4096 rows and to stock 1.0.0 (5/5, both boots), and the needle is found
(prefill 79.8 and 80.2 s, against 73.9 and 74.9 s with 4096 rows). GPU recheck for the batch blocker, on the fixed stack with every PR applied: golden 6/6, `exact.py` and `--pad 3k` PASS, toolcheck 3/3, needle found, and the bench_draft, exact_prefill and FILL=0 probes byte-identical to stock 1.0.0 (details in the batch note on #34).
