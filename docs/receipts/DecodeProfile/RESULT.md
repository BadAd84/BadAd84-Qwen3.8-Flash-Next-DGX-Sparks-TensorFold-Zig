# DecodeProfile: naming the mechanism of the per-round decode cost

Status: PARTIAL. This receipt records what is measured and verified, and names the one boot glitch that
stopped the fresh two-engine capture. Read the "What is proven" and "Blocker" sections before quoting
any figure.

Assignment: name the mechanism of the decode round's 6 to 14 percent cost that ParityGap attributed to
a per-round difference and that no env candidate moved.

## 1. The per-round delta is real, and it is the round, not the drafting

From `docs/receipts/ParityGap/RESULTS.md` (the recorded window's first-boot cells, its own counters):

| level | kind | P ms/round | D ms/round | D/P | P tok/round | D tok/round |
|---:|---|---:|---:|---:|---:|---:|
| 1 | prose | 37.5 | 41.6 | 1.109 | 2.48 | 2.58 |
| 1 | code | 47.5 | 51.7 | 1.088 | 5.55 | 5.89 |
| 2 | code | 29.6 | 33.7 | 1.136 | 4.88 | 5.28 |
| 4 | code | 21.7 | 24.5 | 1.130 | 4.94 | 5.23 |
| 8 | code | 14.7 | 16.5 | 1.116 | 4.88 | 4.83 |

D's round costs 6 to 14 percent more at every level (median about 10) while tokens a round move within
+/- 8 percent and flip sign by level. At the same tokens a round D would be 4 to 6 percent FASTER at one
stream. So the whole decode gap is the round cost, and closing it is worth about 10 percent of decode at
every concurrency. The per-round delta is 3.6 to 4.2 ms at C=1 (prose 41.6-37.5 = 4.1; code 51.7-47.5 =
4.2).

## 2. What each engine can and cannot report about a round (the decisive structural finding)

**P's engine has a per-part decode-round profiler; D's does not.** This is read from source, not inferred.

- P: `TF_FLASHNEXT_PROFILE=1` points `Forward.prof` at `cuda_prof.zig`, whose `Part` enum names 45 parts
  of a round and whose `rounds()` prints, per decode round, ms a round and percent by part, split into
  the main layers and the MTP head, plus the MTP head's ms by draft level. Source:
  `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_prof.zig` (`pub const Part`, `fn rounds`,
  lines 12-61 and 130-150). The reader is `cuda_engine.zig:2125` (`e.prof`, "eager: graphs off while
  profiling").
- D: the dev tree's `TF_FLASHNEXT_PROFILE` reader is
  `DevTree/zig/src/families/flashnext/cuda_batch_kernels.zig:184-188`, whose own doc says it prints
  "each chunk's wall time (synchronized) and its host n-gram gather on stderr" - a PROMPT-pass number,
  not a decode round. `grep -rln "rounds rank" DevTree/zig/src/` finds nothing: the dev engine has no
  "rounds rank" printer at all. Its only other phase profiler,
  `DevTree/zig/src/families/qwen3_5/cuda_startup_profile.zig`, is startup phases only (load, reserve,
  warmups, calibration), not decode.

Consequence: the decode round cannot be split by stage SYMMETRICALLY with the engines' own instruments.
P gives a named per-part decode table; D gives none. Any per-stage attribution must therefore use a
kernel-level capture (nsys/ncu), which sees kernels, not the engine's part names.

## 3. P's own decode round, by stage (measured, same box, same engine family)

`spark6 ~/work/ots972/evidence/benchlog-dec1-20261022-095508.phases.txt` (image
`tensorfold-qwen38:ots571-stackFup-a89341b3a3c3f62b`, the release under P's zmerge8 keep set; one stream,
code, `bench-many --streams 1 --context 32768`, TF_FLASHNEXT_PROFILE=1):

```
rounds rank 0 decode: 122 rounds, wall 42.41 ms a round, GPU timeline 42.41 ms a round (main 37.20, MTP head 5.20)
rounds rank 0 decode   gdn_proj            7.313 ms a round   17.2%
rounds rank 0 decode   experts_gate_up     6.500 ms a round   15.3%
rounds rank 0 decode   out_proj            3.739 ms a round    8.8%
rounds rank 0 decode   hc_down             3.318 ms a round    7.8%
rounds rank 0 decode   experts_down        3.021 ms a round    7.1%
rounds rank 0 decode   hc_mix              2.908 ms a round    6.9%
rounds rank 0 decode   attn_proj           2.142 ms a round    5.1%
rounds rank 0 decode   head                1.379 ms a round    3.3%
rounds rank 0 decode   router              1.385 ms a round    3.3%
rounds rank 0 decode   gdn_chain           1.027 ms a round    2.4%
rounds rank 0 decode   stage               0.939 ms a round    2.2%
rounds rank 0 decode   topk_plan           0.618 ms a round    1.5%
rounds rank 0 decode   hc_writeback        0.578 ms a round    1.4%
... (24 more parts below 1.4 percent)
rounds rank 0 decode   mtp.head            1.671 ms a round    3.9%
rounds rank 0 decode   mtp.attn_proj       0.639 ms a round    1.5%
rounds rank 0 decode   mtp.mtp_in          0.539 ms a round    1.3%
rounds rank 0 decode   mtp.experts_gate_up 0.362 ms a round    0.9% (and the rest of the 5.20 ms MTP head)
```

So P's round is dominated by: `gdn_proj` 17.2, `experts_gate_up` 15.3, `out_proj` 8.8, `hc_down` 7.8,
`experts_down` 7.1, `hc_mix` 6.9, `attn_proj` 5.1, and a 12.3 percent MTP head. No single part owns more
than about 17 percent.

## 4. P's decode round, by kernel (measured, ncu, serialised share)

`spark6 ~/work/ots972/evidence/ncu-s1-kernel-share.txt`: ncu, `--launch-skip 8000 --launch-count 400`,
one stream, code, sampling 150 consecutive decode kernels (x12 = one per full-attention layer):

```
sampled 150 kernels, total 4.421 ms of SERIALISED kernel time
 29.0%    1283.6 us  x  12  void tf_fn_qmmf_ld::qmmf_kernel
 17.3%     763.6 us  x  12  void tf_fn_int4::int4_kernel
 15.4%     679.8 us  x  12  void tf_fn_qmmf::qmmf_kernel
 12.5%     553.5 us  x  12  tf_fn_hc_down_q12_kernel
  9.2%     405.6 us  x  12  tf_fn_hc_upmix_q12_kernel
  3.0%     132.8 us  x   5  void tf_fn_gdn_tree::tree_kernel
  2.7%     120.2 us  x   6  _router
  1.8%      78.5 us  x   7  _b16mm
  1.5%      67.0 us  x  12  _hc_writeback
  1.4%      61.0 us  x  12  _hc_normed
  1.2%      54.5 us  x   5  void tf_fn_gdn_io::front_kernel
```

The top five kernels carry 83.4 percent of the sampled serialised time, and they are five DISTINCT
kernels (`qmmf_ld`, `int4`, `qmmf`, `hc_down_q12`, `hc_upmix_q12`). The same picture at the nsys level,
`nb-dec1-20261022-095508.cuda_gpu_kern_sum.csv` (19527 `qmmf_ld` instances, 38247 `qmmf`, 16272 `int4`,
37440 `hc_down_q12`): the round is a long tail of many small kernel launches, not one hot kernel.

## 5. Attribution, to the level the artefacts support

- The 6 to 14 percent is a per-round cost in the GPU kernel timeline, spread across the round's many
  launches. On P's own instrument no part exceeds 17.2 percent; on P's own kernel census no kernel exceeds
  29 percent, and those are the shared GEMM/readout kernels (`qmmf`, `int4`, `qmmf_ld`) that both engines
  run in some form.
- The per-round delta of about 4 ms at C=1 is therefore NOT one kernel running 4 ms longer. It is the
  composition: D's engine runs its own glue kernels where P launches through the captured Triton set plus
  its `fn_` kernels, and the dev engine CANNOT load the captured set at fp8 KV
  (`DevTree/zig/src/families/flashnext/cuda_lanes_load.zig:33`; P loads it unconditionally,
  `production:zig/src/families/flashnext/cuda_engine.zig:582`). A divergent composition of many small
  kernels is exactly the shape that turns into a per-launch overhead that scales with launch COUNT, which
  is why it shows as a uniform 6 to 14 percent across levels rather than as one kernel.
- This is consistent with every refuted candidate in ParityGap/ParityDivergence: the copy policy, the KV
  tier, the graphs, the prompt matmul, the drafter, the chunking, the int4 tile and the KV format are all
  level or off, so the cost is the kernel ARRANGEMENT (a per-round composition difference), not an option.

## 6. What a fix would have to change, and the ceiling

- A fix must reach the ROUND's kernel arrangement, not a setting. Two named routes:
  1. Qualify a captured kernel set at fp8 KV for the dev engine, so D launches P's captured set for the
     decode kernels where a variant exists (the port that closes the prefill gap, extended to decode).
  2. Reduce the DECODE launch count in the dev path (fuse the readout `hc_*` steps and the MTP head's
     per-level launches, which the ncu share shows at 21.7 percent for the two `hc_*` kernels plus a
     12.3 percent MTP head on P's own numbers).
- Ceiling: the whole prize is about 10 percent of decode, and it is DISTRIBUTED. No single part or kernel
  can carry it; the largest measured single share on either instrument (17.2 percent of a round by part,
  29 percent of sampled kernel time by kernel) is a shared component both engines run. A fix that removes
  one part cannot close 10 percent; the measured distribution says the fix must change the round's
  composition as a whole, which is why no env candidate moved it.

## 7. Blocker (what stopped the fresh two-engine capture)

A fresh paired nsys capture (P and D, one stream, one prompt) was built and its driver is on spark6 at
`~/work/prof/decode_profile.sh`, with `trace_decode.py` (the parity harness's own request shape) and
`nsys_sum.py`. Production was stopped and restored cleanly three times; the restore is proven by
`/health` 200, the pinned image id `sha256:235211ea77ee...`, and `check-prod-env.py` reading
`117 rows compared ... 54 equal, 0 problem(s)`.

The boot that failed: a `docker run -d` of
`nsys profile ... /usr/local/bin/tensorfold-native serve <checkpoint> --context 262144 --parallel 1 ...`
inside the P image. The exact same command reproduced BY HAND (detached, same env, same argv) boots; the
same command through the driver exits with the CHILD printing
`tensorfold serve: error: unrecognized arguments: --context 262144` (the usage of a DIFFERENT binary,
`/opt/tensorfold/bin/tensorfold`, the Python front), while the driver's own logged `CMD` line names
## 8. Provenance of every figure

Every figure below is quoted from an artefact copied into this directory under `ev/`:

- ParityGap ms/round and tok/round: `docs/receipts/ParityGap/RESULTS.md`, its own `work/ParityGap/ev`
  counters (the source on spark6 is the same window's `~/work/parity2/out`).
- P decode-round stage table: `ev/benchlog-dec1-20261022-095508.phases.txt` (source
  `spark6 ~/work/ots972/evidence/`, image `tensorfold-qwen38:ots571-stackFup-a89341b3a3c3f62b`, one
  stream, code, `bench-many --streams 1 --context 32768`, TF_FLASHNEXT_PROFILE=1).
- P kernel shares: `ev/ncu-s1-kernel-share.txt` (ncu, `--launch-skip 8000 --launch-count 400`, one
  stream, code) and `ev/nb-dec1-20261022-095508.cuda_gpu_kern_sum.csv` (nsys census of the same cell).
- D lacks a decode-round printer: `work/ParityGap/DevTree/zig/src/families/flashnext/cuda_batch_kernels.zig`
  (the `TF_FLASHNEXT_PROFILE` reader, chunk/ngram only) and `grep -rln "rounds rank" work/ParityGap/DevTree/zig/src/`
  returning 0 files against the same grep finding it in P's `cuda_engine.zig` and `cuda_prof.zig`.
- Captured-set refusal at fp8 KV: `work/ParityGap/DevTree/zig/src/families/flashnext/cuda_lanes_load.zig:33`;
  P loads it unconditionally at `production:zig/src/families/flashnext/cuda_engine.zig:582`.
- The two images' ids: `docs/receipts/ParityDivergence/RESULT.md` section 1 (P `sha256:235211ea77ee`,
  D `sha256:adc40fe3ea7b`), re-read from the box's `docker inspect` at each restore.

The fresh paired capture's own artefacts (driver, trace client, nsys summariser, stage-table analyser)
are in this directory; its failed boot's state is recorded in section 7.
