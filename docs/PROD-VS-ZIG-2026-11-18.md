# Production against our Zig stack, one window (spark6, 2026-11-19)

Same-window comparison of the serve the owner runs on spark6 (production) against our current Zig stack, at 1, 2, 4,
6 and 8 streams, prose and code, on production's own checkpoint and on ours. Every number comes from this window's
run records, copied to `work/ProdVsZig/box/out2/` (spark6 `~/work/pvz/out2/`); each cell names its directory.

## What was compared

| arm | checkpoint | engine source | image |
|---|---|---|---|
| `prod` | `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` @ `1464274120d3`, as it serves today | its own launcher (`~/qwen6-start-prod.sh`), recipe 1.0.0 @ `364f21a` (`~/qwen-zig-prod`), TensorFold `5c3e3e29` + the zmerge8 keep set + the 64K boot fix | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` |
| `int4` | the same INT4-AutoRound checkpoint | upstream `964174ea05` (`v1.2.9-33`) + `patches/main-964174ea05` 0001-0019 + `patches/main-964174ea05-int4` (`0020-int4-autoround`) | `tensorfold-qwen38:pvz-int4` |
| `fp4` | `nvidia/Qwen3.8-Flash-Next-FP4-Local` @ `b9ce18a6887e` | upstream `964174ea05` + `patches/main-964174ea05` 0001-0019 | `tensorfold-qwen38:pvz-fp4` |

`int4` is the like-for-like arm: same checkpoint, same routing width, token-identical replies. `fp4` is the checkpoint
our own serve is built for, so against production it is a cross-checkpoint comparison and is labelled as one.

### Why both arm images were built here

No image of either stack existed. `docker images tensorfold-qwen38` held no tag for the 19-patch series (the
2026-11-15 window's `um96`/`rs96`/`rq7` are gone), and `patches/main-964174ea05-int4/RECORD.md` records the INT4
re-seat as "**NOT built into an image or served on this base**". Both were built inside the window's own GPU-lock
hold with the recorded script `scripts/qwen38/zig/target/build_patches.sh` (copied to `~/work/pvz/build_patches.sh`,
sha256 `41fbe8ec85c7bc4eeb5334db3217c6de56a039081c3cd2f8499122a911601d67`), which fetches upstream at the ref, applies
the patches in filename order and builds `fatbins install native`:

    build_patches.sh pvz-fp4  git://192.168.99.16/up-pr/tf 964174ea05879e6dde1de1198a3aae3ef8b46a3b ~/work/pvz/patches-fp4
    build_patches.sh pvz-int4 git://192.168.99.16/up-pr/tf 964174ea05879e6dde1de1198a3aae3ef8b46a3b ~/work/pvz/patches-int4

- `patches-fp4/` is `patches/main-964174ea05` verbatim; `sha256sum -c SHA256SUMS` passes on the box.
- `patches-int4/` is the same 19 plus `0020-int4-autoround.patch`, byte-identical (`2888d1d2c34e...`) to
  `patches/main-964174ea05-int4/0016-int4-autoround.patch` under a name that sorts last, because the build script
  applies `*.patch` in glob order and the INT4 patch must follow 0019.
- Build logs: `work/ProdVsZig/box/out/build-pvz-fp4.log` and `build-pvz-int4.log`. Their `patches: N from ...` line
  and the `git fetch ... 964174ea05879e6dde1de1198a3aae3ef8b46a3b` layer are the images' provenance, and both end
  `BUILT` (`rc=0 450s` and `rc=0 417s`).

### Two windows, and why

The first window (2026-11-19 01:38-02:07 UTC, `work/ProdVsZig/box/out/`) built both images and measured production at
all five stream counts, but **every one of our arms failed to boot in 0 s**:

    [start.sh] ERROR: tensorfold-qwen38:pvz-int4 is not an image of this recipe (tf.kernels=present): scripts/prepare.sh --rebuild

Both arm images inherit `tf.kernels=present` from the base `tensorfold-qwen38:zig-db28187`, while the recipe served
here gates on `embedded` (`start.sh` line 118). The campaign's own 5-second tool fixes it without a rebuild:

    ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:pvz-fp4  embedded  -> label=embedded id=sha256:8add34dd1faa...
    ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:pvz-int4 embedded  -> label=embedded id=sha256:334c85420027...

The second window relabels both images and re-runs the **whole** 15-cell set, production included, so the comparison
below is one window again. Window 1's production cells are quoted beside window 2's as a window-to-window check.

### Environment each arm ran with

    prod: HOST=127.0.0.1 PARALLEL=<streams> LOCK_HOLDER=0, otherwise ~/qwen6-start-prod.sh unchanged
          (fp8 KV, 262144-token window, vision on, drafts on, TF_FLASHNEXT_MTP_FP8 overlay, its own 52 settings)
    int4: the recipe's settings plus
          TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15
          TF_FLASHNEXT_SHARED_DRAFTS=0   (2 streams and up)
          TF_FLASHNEXT_GREEDY_WIDE=8 TF_FLASHNEXT_KV_PAGES=4096   (6 and 8 streams)
          CHECKPOINT=int4 IMAGE=tensorfold-qwen38:pvz-int4 VISION=0 KV_DTYPE=fp8 CONTEXT=262144
    fp4:  the recipe's settings plus
          TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1
          TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8 TF_FLASHNEXT_KV_PAGES=4096 (6 and 8 streams)
          CHECKPOINT=nvfp4 IMAGE=tensorfold-qwen38:pvz-fp4 VISION=0 KV_DTYPE=fp8 CONTEXT=262144
          (no TF_FLASHNEXT_HC_Q12, as the FP4 block recommends)

The environment each cell actually got is in `<cell>/env.txt` (the container's own `TF_FLASHNEXT_*`/`TENSORFOLD_*`),
and the serve line in `<cell>/boot.log` proves the binding (`--host 127.0.0.1 --port 8888`) for all three arms.
Production ran with vision on because that is how it serves; our arms ran with vision off, which is how every table in
`patches/*/README.md` was measured.

## Method

One GPU window on spark6 from 08:38 to 09:19 UTC, inside one hold of `~/work/gpu.lock` (taken FIFO), 15 cells.

- A cell is one arm at one stream count and is a fresh boot through the recipe's `start.sh restart` (production
  through its own launcher), then golden, then (at one stream) TTFT, then one decode pass.
- Cells are interleaved and the order reverses every other stream count: 1 `prod,int4,fp4`; 2 `fp4,int4,prod`;
  4 `prod,int4,fp4`; 6 `fp4,int4,prod`; 8 `prod,int4,fp4`.
- GPU temperature and SM clock are read at the start of every cell (the GB10 thermal rule). Temperatures sat between
  41 and 60 C at the cell boundaries, quoted per cell in the thermal table below.
- Decode is `~/work/lanes/tfmain/tfm_decode.py LABEL C out.jsonl 1`, the harness every earlier table used: C
  barrier-started greedy requests, thinking off, 512 tokens, distinct prompts, a per-pass nonce so every prompt is
  cold; per request `decode tok/s = (completion tokens - 1) / (elapsed - ttft)`; aggregate = the sum of the C
  per-request rates; the engine's rounds, drafted and accepted counters are read from `/metrics` around each pass.
- Exactness: `~/work/qf_harness.py golden` (six greedy prompts, 256 tokens) at every boot, compared with
  `~/work/zgold_cmp.py` against production's first boot.
- TTFT: `~/work/bench/ttft.py 8888 --sizes 1k,8k,32k --thinking off,on --loads idle --warm-add 0 --reps 3`, at one
  stream, cold prompts (a fresh UUID salt each), server idle.
- No outside traffic: sparkDash (CT111) was stopped for the window and every arm is bound to `127.0.0.1`. spark6 has
  no passwordless sudo, so the `:8888` iptables rule this repo's AGENTS.md describes could not be applied; the
  loopback binding is what makes it unnecessary, and the binding is quoted per arm rather than assumed.
- One pass an arm a cell, so no cell can meet the two-runs noise rule; the fp4 arm repeats the 2026-11-15 measurement
  of the identical stack, and that repeat is the noise control (below).

## Results: production against our stack on production's own checkpoint

Aggregate tok/s (prose / code) and per-stream median after the semicolon. Records: `work/ProdVsZig/box/out2/<cell>/dec.jsonl`.

| streams | ours (`int4-c*`) | production (`prod-c*`) | ours / production |
|---:|---|---|---|
| 1 | 65.0 / 122.2; 65.0 / 122.2 | 69.4 / 125.4; 69.4 / 125.4 | 0.94 / 0.97 |
| 2 | 100.9 / 163.7; 50.5 / 81.8 | 116.5 / 178.5; 58.2 / 89.3 | 0.87 / 0.92 |
| 4 | 146.7 / 232.7; 37.4 / 60.0 | 165.3 / 257.8; 41.5 / 65.5 | 0.89 / 0.90 |
| 6 | 176.4 / 291.7; 29.3 / 49.4 | 207.2 / 330.9; 35.2 / 55.3 | 0.85 / 0.88 |
| 8 | 195.6 / 334.5; 24.6 / 42.7 | 239.8 / 384.1; 30.3 / 47.9 | 0.82 / 0.87 |

Tokens a second of wall time (all streams' tokens over the batch wall), the same cells:

| streams | ours prose / code | production prose / code |
|---:|---|---|
| 1 | 64.3 / 120.1 | 68.6 / 123.2 |
| 2 | 96.2 / 160.0 | 109.5 / 167.7 |
| 4 | 135.0 / 202.3 | 149.3 / 227.1 |
| 6 | 160.5 / 253.5 | 188.5 / 292.3 |
| 8 | 179.2 / 290.2 | 217.0 / 339.1 |

Rounds / drafted / accepted (prose then code) from the engine's own counters, same cells:

| streams | ours | production |
|---:|---|---|
| 1 | 170/498/341 ; 73/615/438 | 186/497/325 ; 81/602/430 |
| 2 | 371/857/652 ; 173/1166/849 | 356/936/666 ; 192/1102/830 |
| 4 | 792/1671/1190 ; 373/2216/1671 | 737/1785/1201 ; 405/2108/1639 |
| 6 | 1163/2605/1842 ; 541/3443/2525 | 1098/2722/1863 ; 596/3192/2470 |
| 8 | 1556/3354/2359 ; 763/4333/3325 | 1468/3550/2372 ; 816/4215/3272 |

So at one stream ours takes fewer rounds than production on both prompt sets and lands within 3% on code; from two
streams up ours takes 4 to 11% more prose rounds while code rounds stay 5 to 9% below production's.

## Results: our checkpoint

`fp4` is our production candidate and serves the FP4 checkpoint, so this table is cross-checkpoint: the same
production cells as above against ours on our own model.

| streams | ours (`fp4-c*`) | production (`prod-c*`) | ours / production |
|---:|---|---|---|
| 1 | 63.4 / 84.7; 63.4 / 84.7 | 69.4 / 125.4; 69.4 / 125.4 | 0.91 / 0.68 |
| 2 | 89.6 / 126.2; 44.8 / 63.1 | 116.5 / 178.5; 58.2 / 89.3 | 0.77 / 0.71 |
| 4 | 117.3 / 170.3; 29.7 / 43.3 | 165.3 / 257.8; 41.5 / 65.5 | 0.71 / 0.66 |
| 6 | 151.9 / 216.8; 25.9 / 36.7 | 207.2 / 330.9; 35.2 / 55.3 | 0.73 / 0.66 |
| 8 | 169.3 / 250.2; 21.3 / 32.1 | 239.8 / 384.1; 30.3 / 47.9 | 0.71 / 0.65 |

Its rounds (prose/code): 143/88, 321/177, 697/400, 994/582, 1356/802. On code that is 7.9% fewer tokens a round than
production at one stream (512 tokens in 88 rounds against 81), which is the drafter difference the earlier reports
attributed to the two models' heads, not to policy.

## Exactness

- `int4` against production: **6/6 identical in all five cells**, token hashes included
  (`golden ... : 6/6 identical` at `int4-c1`, `c2`, `c4`, `c6`, `c8`).
- `prod` against its own first boot: 6/6 in all four later cells.
- `fp4` against production: 4/6, as expected between different checkpoints (the two long replies differ: `golden-1`
  215 against 214 tokens, `golden-4` the same length but different content).
- `fp4` against its own 2026-11-15 golden (image `rs96`, the identical stack): **6/6 identical**, same token counts
  (`work/ProdVsZig/prev/zgold-rs96-c1.json`).

## Time to first token (cold prompts, idle, one stream; median seconds)

| prompt | ours `int4` | production | ours `fp4` |
|---|---:|---:|---:|
| 1k, thinking off | 0.470 | 0.477 | 0.532 |
| 1k, thinking on | 0.464 | 0.494 | 0.537 |
| 8k, off | 2.923 | 2.886 | 3.433 |
| 8k, on | 2.957 | 2.769 | 3.312 |
| 32k, off | 12.120 | 10.680 | 13.654 |
| 32k, on | 12.101 | 10.769 | 13.604 |

All three arms' `ttft.py` runs exited 0 with no excluded samples (`<cell>/ttft.log`). Our INT4 arm is level with
production at 1k and 8k and 13% slower at 32k; our FP4 arm is 11 to 19% slower at 1k and 8k and 28% slower at 32k,
which is the prompt-pass cost on the checkpoint with ten routed experts.

## Thermal state at each cell

`temp C, SM clock` read immediately before each boot (`window.log`, `=== cell ... gpu`):

| cell | start | cell | start | cell | start |
|---|---|---|---|---|---|
| prod-c1 | 41, 2405 MHz | int4-c1 | 56, 208 MHz | fp4-c1 | 58, 208 MHz |
| fp4-c2 | 60, 208 MHz | int4-c2 | 54, 208 MHz | prod-c2 | 47, 208 MHz |
| prod-c4 | 47, 208 MHz | int4-c4 | 47, 208 MHz | fp4-c4 | 47, 208 MHz |
| fp4-c6 | 50, 208 MHz | int4-c6 | 52, 208 MHz | prod-c6 | 47, 208 MHz |
| prod-c8 | 49, 208 MHz | int4-c8 | 51, 208 MHz | fp4-c8 | 49, 208 MHz |

The 208 MHz reading is the GB10's idle clock between boots, not a running clock; it is recorded because the rule asks
for it, and the temperature is the comparable quantity. Every cell sat between 41 and 60 C, so no arm was read from a
heat-soaked box and none from a cold one.

## The previous numbers, beside the new ones

| streams | int4, previous (1.2.7, 2026-11-14) | int4, new | change | fp4, previous (`rs96`, 2026-11-15) | fp4, new | change |
|---:|---|---|---|---|---|---|
| 1 | 71.4 / 125.6 | 65.0 / 122.2 | -9.0% / -2.7% | 63.7 / 85.3 | 63.4 / 84.7 | -0.4% / -0.7% |
| 2 | 109.4 / 169.7 | 100.9 / 163.7 | -7.7% / -3.5% | 89.6 / 127.0 | 89.6 / 126.2 | -0.0% / -0.7% |
| 4 | 151.6 / 239.6 | 146.7 / 232.7 | -3.3% / -2.9% | 117.2 / 170.1 | 117.3 / 170.3 | +0.1% / +0.1% |
| 6 | 186.1 / 297.1 | 176.4 / 291.7 | -5.2% / -1.8% | 151.5 / 216.5 | 151.9 / 216.8 | +0.3% / +0.1% |
| 8 | 199.0 / 340.1 | 195.6 / 334.5 | -1.7% / -1.7% | 169.2 / 249.8 | 169.3 / 250.2 | +0.1% / +0.2% |

Production across the two windows of this session (same launcher, same settings): 71.3/127.5 and 69.4/125.4 at one
stream, 120.4/179.6 and 116.5/178.5 at two, 168.6/261.6 and 165.3/257.8 at four, 212.0/333.9 and 207.2/330.9 at six,
243.4/384.7 and 239.8/384.1 at eight. The earlier evenings gave 71.2/129.5, 119.8/180.8, 164.7/261.9, 210.3/328.2 and
242.4/380.0 (`patches/1.2.7-int4/README.md`).

## Which cells moved, and what could explain it

**The FP4 arm did not move.** It is the same 19 patches on the same upstream base with the same block as the
2026-11-15 run, and every cell lands within 0.7% of it, with its golden 6/6 identical and the same token counts. That
repeat is the window's noise floor: below about 1% no cell here means anything.

**Our INT4 arm is 1.7 to 9.0% slower than the 1.2.7 INT4 port was, most at one stream.** The cause is not the
drafter: at one stream the rounds are identical to that measurement (170 prose / 73 code now, 170 / 73 then), so the
same work is being done per token and the per-round time grew. It is also not the engine or the base alone, because
the FP4 arm on that base and those patches is level with its own earlier run. What changed only for this arm is the
INT4 port itself: the re-seat moved it from v1.2.7 to upstream `964174ea05` and had never been booted, and its two
recorded resolutions (`patches/main-964174ea05-int4/RECORD.md`) both sit on paths only the INT4 checkpoint takes, the
BF16 MTP experts' recode in front of upstream's shared block-FP8 reader and the scratch estimate's extra slot row.
The drafter settings are not implicated either: they are the same block as then, and at one stream the counters match.
A per-kernel log on this base is the next thing needed to place the loss, and this window did not take one.

**Against production on the same checkpoint, ours is 0.94/0.97 at one stream, then 0.82 to 0.89 on prose and 0.87 to
0.92 on code from two streams up.** The one-stream cells are the best this comparison has ever read (the 2026-11-14
window had 1.00/0.97 for the 1.2.7 port; today's production cells are 1.1 to 2.8% lower on prose and within 1.1% either
way on code, so the ratios are not directly comparable and the absolute tokens are the honest pair).

**Cross-checkpoint, our FP4 serve is 0.65 to 0.91 of production**, widening with streams, which is the same shape as
every earlier window; the checkpoint carries most of it, as `docs/INT4-PORT.md` showed by serving production's own
model on our engine.

## Restore

The window's EXIT trap stopped the serve, ran production's own launcher and polled `/health`:

    === 2026-11-19T09:19:13+00:00 cells done
    === 2026-11-19T09:20:52+00:00 restored health 200
    === 2026-11-19T09:20:52+00:00 window done

`work/ProdVsZig/box/out2/health-restored.txt` holds the body (`{"status": "ok", "model": "Qwen3.8-Flash-Next", ...
"max_batch_size": 8, "warming": false}`) and `restored-container.txt` reads
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 running`. The first window restored the same way at 02:07:34
(`work/ProdVsZig/box/out/restore-status.txt`).
