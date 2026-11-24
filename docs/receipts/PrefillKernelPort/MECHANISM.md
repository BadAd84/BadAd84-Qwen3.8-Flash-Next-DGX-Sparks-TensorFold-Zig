# Cold-prefill prompt-matmul lever: mechanism map

Scope: the p re-fill gap ParityGap attributed to the prompt-matmul path (`docs/receipts/ParityGap/RESULTS.md`,
section "A2: the captured prompt-matmul path is the cold-prefill gap"). This file records what the two forms
actually are, what the dev engine already has, and which route is real. Sources are quoted with their file and
line; nothing here is inferred from a sample corpus.

## 1. Production's form: `_b16mm_ks` / `_fp4mm_ks` (captured Triton kernels)

The production overlay adds two Triton kernels per prompt-matmul specialization:

- source `src/tensorfold/families/qwen4_exp/cuda/prompt_mm.py`, `_b16mm_ks` at line 24 and `_fp4mm_ks` at line 64
  (`git show production:src/tensorfold/families/qwen4_exp/cuda/prompt_mm.py`);
- the packer `tools/zig/flashnext_prompt_spec.py` (on the production branch, and in the dev base) derives one
  `_b16mm_ks`/`_fp4mm_ks` entry for every `_b16mm`/`_fp4mm` spec entry with `BM=128`, shape-driven `SK>1` and a
  runtime `M`, dropping the `PART` argument and adding `GROUP`; its own line reads
  `GROUP = 8  # _b16mm_ks: row tiles a band (the tile order; no bits depend on it)`;
- the packer `tools/zig/aot_pack.py` builds the sm121 kernel set the production engine loads
  (`production:zig/src/families/flashnext/cuda_engine.zig:582` `e.set = try cuda.aot.Set.load(...)`, unconditional).

What `_b16mm_ks` computes, from its own docstring: one program a (rows, columns) tile runs every K slice itself;
slice `s` is exactly what `_b16mm` program `pid_s = s` computes (same K blocks, same order, same loads, dots and
scale steps, an accumulator from zero); the slice totals are added as `_reduce` adds them (`total = p0`, then
`total = total + p_s`), then stored as `_reduce` stores them (fp32 or one bf16 rounding). Its tile constants:
`BM=128`, `BLOCK_N=64`, `BK=64`, `GROUP=8`, and one program a (rows, columns) tile on a 1-D grid in bands of
`GROUP` row tiles (all column tiles of a band before the next band, so a band's rows stay in L2).

Its launch grid, from the kernel (`pid = tl.program_id(0)`; `band = pid // (GROUP * tiles_n)`; `tiles_n =
cdiv(N, BLOCK_N)`; `tiles_m = cdiv(M, BM)`): `cdiv(M,128) * cdiv(N,64)` programs, ordered band of 8 row tiles
first, column tiles inside a band.

Production's A/B switch: `TF_FLASHNEXT_PROMPT_MM=0` (`production:zig/src/families/flashnext/cuda_prompt.zig:8`
`pub const env = "TF_FLASHNEXT_PROMPT_MM";`) keeps Python's two launches (`_b16mm` + `_reduce`), boot line
`prompt path: ... matmul K slices split with _reduce` (`production:zig/src/families/flashnext/cuda_engine.zig:783`);
the default reads `matmul K slices in one program (_b16mm_ks/_fp4mm_ks)`.

## 2. The dev engine's path: it ALREADY runs the one-program K-sliced form

This is the load-bearing finding for the route decision, and it corrects the mechanism sentence in `RESULTS.md`.

The dev engine's prompt matmuls go through `cuda.qmmf.Lane.matmulOut`
(`DevTree/zig/src/cuda/qmmf.zig:339`), reached from `cuda_tiles.matmul` (`DevTree/zig/src/families/flashnext/cuda_tiles.zig:36`)
with `prompt = self.hooks.prompt`, set true for the prompt fill
(`DevTree/zig/src/families/flashnext/cuda_lanes.zig:360-361` `.prompt = true`).

`planSlices` (`qmmf.zig:91`) sets `fused = sk > 1 and m >= fused_rows` with `fused_rows = 256` (`qmmf.zig:16`).
`usesPrompt` (`qmmf.zig:333`) requires `!p.cluster and !p.reduce`, so a prompt-width `SK>1` call has
`fused=true, cluster=false, reduce=false`. `matmulOut` then picks
`f = l.prompt.?[out][@intFromBool(p.fused)]` (`qmmf.zig:352`) with `bm=128` (`qmmf.zig:346`).

The loaded instances are `qmmf_kernel<BF16,128,128,2,4,3,F32,false,FUSE>` for `FUSE` in {false,true}
(`DevTree/zig/kernels/cuda/qmmf.cu:393-400` `BF16_PROMPT`), loaded by `Lane.loadPrompt` on sm_12x
(`qmmf.zig:262`, gated `if ((try d.currentCapability()) / 10 != 12) return;`, and GB10 is sm_121 so `121/10 = 12`).
The `FUSE=true` instance walks every K slice in one program and adds the slice totals in slice order:
`qmmf_body.cuh:151-159` (`if (it > 0 && it % slice_groups == 0) { tot = it == slice_groups ? acc : tot + acc; }`)
with `per = FUSE ? KG : slice_groups` (`qmmf_body.cuh:19`) and `slice = FUSE ? 0 : blockIdx.z`
(`qmmf_body.cuh:22`). That is exactly `_b16mm_ks`'s "one program runs every slice, slice totals added in slice
order, no `[SK, M, N]` fp32 buffer".

So the dev engine does NOT run "two launches" at a prompt-width `SK>1` matmul. Its own host test pins the
selection: at `m=4218, sk=4` `matmulOut` issues one call (`Trace.calls == 1`) on the fused prompt instance
(`qmmf.zig:655-663`, ids 21/23, `prompt_shared`). The dev's boot line agrees in kind: production's equivalent
print names the captured kernel, the dev prints `own glue kernels` and its prompt tiles come from its own sm121
cubin.

Consequence: `RESULTS.md`'s sentence "D's tree contains no such form at all (`grep b16mm|fp4mm` over
`work/ParityGap/DevTree/zig` finds nothing)" is literally true for the SYMBOL and false for the FORM. The dev
engine has the form under another name. A port that adds "the form" would duplicate an existing capability and
would be a no-op against the measured prefill gap.

## 3. What actually differs: geometry, not launch count

The dev's fused prompt tile and the captured `_b16mm_ks` differ in three tile constants, all from the quoted
sites:

| constant | production `_b16mm_ks` | dev fused prompt tile | site |
|---|---|---|---|
| row tile BM | 128 | 128 | `flashnext_prompt_spec.py` `bms=(128,)`; `qmmf.cu:394` |

| column block | 64 (`BLOCK_N`) | 128 (`BN`) | `_b16mm_ks` grid `cdiv(N,64)`; `qmmf.cu:394` `128,128` |
| K step | 64 (`BK`) | 64 (`GS`) | `_b16mm_ks` `BK=64`; `qmmf_body.cuh` `GS=64` |
| band (tile order) | 8 row tiles (`GROUP=8`) | computed `band = max(1, min(rows_t, 12MiB/(bm*k*2)))` | `flashnext_prompt_spec.py` `GROUP=8`; `qmmf.zig:357` |
| staging | Triton, no mbarrier (bulk copies) | `BN=128` uses mbarrier bulk copies (`qmmf_body.cuh:44,60-71`) | `qmmf.cu:44-71` |

The band schedule itself is present in the dev: `tile_of` (`kernels/cuda/common/qmm_frag.cuh:101`) implements the
band `group` parameter (`band = group * cols_t; first = b / band * group; ...`), and the launcher passes its
computed `band` into the kernel's `group` argument (`qmmf.zig:357,364`). So the tile ORDER is the same mechanism
with a different `group` value: dev computes 19 at `bm=128, k=2560` (`12<<20 / (128*2560*2) = 19`), production
pins 8.

## 4. Why the dev engine refuses a captured set at fp8 KV, and whether production's set could load

`cuda_lanes_load.zig:33` (dev): `if (o.kv8 and (o.tp != 1 or captured != null or o.slide)) return
error.Fp8KvUnsupported;` - a captured set (`captured != null`) is refused whenever fp8 KV is on. The dev serves
`KV_DTYPE=fp8` (`patches/main-1ece6e6db-r5-dev/README.md`), so a captured set can never be passed.

Production's set is compiled from a different source (`prompt_mm.py` via `aot_pack.py` from the production
checkout at `db281878` + recipe `3289c9eb`) and its `.cubin` carries no relation to the dev tree's Triton source;
loading it into the dev engine would require (a) lifting the fp8-KV refusal, (b) building and shipping a captured
set from the dev source through the Triton/aot pipeline, and (c) the dev engine already runs a byte-equal fused
form natively. So the captured-set route is the heavier, lower-value one.

## 5. Route decision

Port the FORM's remaining geometry into the dev engine's own CUDA: a **prompt tile at `BLOCK_N=64` with a
configurable band (`GROUP`)**. The mechanism the missing geometry supplies is real and named: production's
`_b16mm_ks` keeps a band of 8 row tiles resident in L2 while its column tiles pass (its docstring: "a band's rows
stay in L2 while its column tiles pass") and reads half the columns per program (`BLOCK_N=64`).

The lever is default-off; off = the dev's current fused prompt tile (BM=128, BN=128, computed band). On = a new
fused prompt tile instance at BM=128, BN=64 with the band pinned to `GROUP` (production's 8 by default).

The lever must equal the dev engine's plain prompt matmul on the same inputs: the new instance keeps the same K16
MMA chain, the same accumulator-from-zero per slice, and the same slice-order fp32 adds (`qmmf_body.cuh` FUSE
path), so its bits are the `_b16mm` + `_reduce` bits the fused form already guarantees. Only the column block and
the tile order change, and `_b16mm_ks`'s own docstring says "a row's or a column's bits never depend on its tile
(its output element is the same MMA instruction sequence), so the tiles and warps are free; the slice boundaries
are not".

## 6. Expected effect, from the A2 arm

ParityGap's A2 (`production` + `TF_FLASHNEXT_PROMPT_MM=0`) showed production's one-program form is worth
`1.121` at cold 8k and `1.136` at cold 32k against its own two-launch fallback, byte-identical replies and decode
unchanged (`RESULTS.md`, "A2"). Reproduced in wall time at C=1: `+0.31 s` per 8k prompt and `+1.31 s` per 32k
prompt, prefill component only. The dev's fused tile is byte-equal to that fallback's bits
(`_b16mm_ks`'s docstring), so any gain the new geometry delivers is measured against the dev's own fused tile,
and the A/B plan (section in the package README) sizes its cells to that effect.

## 7. Status of the deliverable

Shipped as patch 0041 of `patches/main-1ece6e6db-r5-dev` (default off), with its two `dev.env` rows, the three
regenerated serving-pin rows, the package `RECORD.md`/`CHANGES.md` rows and the A/B plan (`AB-PLAN.md`) and its
driver (`driver/`). The gate lines each carry their platform:

| gate | platform | line |
|---|---|---|
| apply, 41 on a pristine `1ece6e6d` | workstation | `applied 41 of 41 (expect 41)` |
| `zig fmt --check build.zig zig` | Paperclip, x86-64 | rc 0 |
| `pincheck.py` | Paperclip, x86-64 | `files 170 failing 0` |
| `check-patch-reverts.py` | workstation | `41 patches, 127 findings, 127 allowed, 0 open, 0 stale` |
| `check-patch-packages.sh` | workstation | `CLEAN (19 package dirs checked, 1 grandfathered)` |
| `check-python.sh` | workstation | `CLEAN` |
| env coverage gate | workstation | `99 settings in scope, set 99, missing 0` |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | Paperclip, x86-64 | rc 0 |
| `zig build -Dnvcc=13.3 compile-cuda-tests` native | Paperclip, x86-64 | rc 0 |

The third compile leg (`-Dnvcc=13.3 -Dtarget=aarch64-linux-gnu`) and the touched host suites
(`test-gradient-serving`, `test-flashnext-int4-host`, `test-qwen-serving-host`, `test-environment-host`,
`test-prompt-cache-host`) are the gate run's remaining rows; the recipe records the same three legs as rc 0 on the
pre-0041 tree, and 0041 changes no host-test behaviour (the 64-column tile is default off).

No device run and no GPU window is claimed or queued. The lever's value is a hypothesis until the A/B window runs:
the expectation (`+0.31 s` at 8k, `+1.31 s` at 32k) is production's captured-vs-two-launch delta, and this lever is
the 64-column geometry on a fused K-slice tile the dev engine already runs, so the window is what decides whether
the geometry carries the captured kernel's advantage.
