# The four candidate shapes: the cache the plan grants, the states it holds, and what an appended turn gains

The owner decides the shape; this file lays the numbers out. Every figure is either a line an engine printed or
arithmetic over such a line. `[M]` marks a measured figure (the source is named), `[D]` marks arithmetic from
measured figures, and the derivation is written next to it.

## 1. The two arithmetic rules every table below uses

**A stream's plan cost.** A stream at a window costs its rows plus a fixed part. Both halves are pinned by two
measured lines from window 4 (NVFP4 image `kv-w1`, `work/KvTierW4/RESULT.md` section 0):

| line | streams | per stream | rows a token | rows at the window | so the fixed part |
|---|---:|---:|---:|---:|---:|
| `8 streams at once, 2.68 GiB each at a 131072-token window (fp8 caches)` | 8 | 2.68 GiB | 18,880 B | 131,072 x 18,880 = 2.305 GiB | 0.38 GiB |
| `4 streams at once, 4.99 GiB each at a 262144-token window (fp8 caches)` | 4 | 4.99 GiB | 18,880 B | 262,144 x 18,880 = 4.609 GiB | 0.38 GiB |

So a stream at a window `W` costs `W x 18,880 B + 0.38 GiB`, and the same 0.38 GiB appears at both windows, which is
what makes the arithmetic below safe. `[D]`, from the two `[M]` lines.

**The cache line.** The plan reports the cache it grants, which is not always the `--prompt-cache-gib` asked:

- `cacheBytes(asked, room, streams)` returns `min(room - streams, asked)` (`zig/src/native/cuda_memory.zig:210-216`):
  the cache cannot take room the streams need.
- on a unified-memory box (a GB10) `hostCacheBudget(asked, ...)` returns `min(asked, available / 2)`
  (`cuda_memory.zig:106-116`): the cache can take at most half of what the host reports available at plan time.

At the eight-slot production shape the measured grant was 3,166 MiB for a 6 GiB ask `[M]`, and the measured plan line
prices 278 pages past it in a 31.0 GiB room; 3,166 MiB sits in the same range as the room the streams leave after
those pages, so which of the two caps bound is not established here. The consequence the owner needs does not depend
on it: on this box, **raising the ask past what the shape leaves does not buy cache**; the shape is the ceiling.

## 2. The state sizes, measured

| conversation | state's rows | state's fixed part | state as measured | source |
|---:|---:|---:|---:|---|
| 32,013 tokens | 604,405,440 B (0.563 GiB) | 113 MiB | 681,530,024 B (0.63 GiB) | W4 eviction probes `[M]` |
| 100,013 tokens | 1.887 GB (1.76 GiB) | 113 MiB | 1.87 GiB; a 105,197-token state read 2,004 MiB | W3 and W4 agent probes; the 2,004 MiB read is this window's turn 6 `[M]` |
| 261,013 tokens | 4.928 GB (4.59 GiB) | 113 MiB | 5,045,068,624 B (4.70 GiB) | W4 kill cells `[M]` |
| 262,144 tokens (the window) | 4,947,201,920 B (4.61 GiB) | 115,642,400 B (110.28 MiB) | 5,062,844,320 B (4.72 GiB) | W5 section 1 `[M]`/`[D]` |

Two more measured facts about the same states:

- one 261k prompt's **whole store footprint** is 5.14 GiB: five state files and 1,019 blocks,
  5,515,339,864 B, because a prompt keeps up to five states (`work/KvTierW4/RESULT.md` section 3); the resident
  endpoint a resume reads is the 4.70 to 4.72 GiB above.
- the state's rows are content addressed and shared: a 105,271-token state file was 111.5 MiB "and 1894 MiB of rows
  it shares", so the file on disk is not the resident size; the cache budgets the resident rows.

## 3. The four shapes

Cache and capacity are for the prompt cache alone: capacity = `floor(cache / state)`, using the measured state sizes
above. A conversation costs one endpoint state; a prompt that keeps several states costs several.

| shape | slots x window | pool | cache the plan grants | states that fit: 32k / 100k / 131k / 261k | conversations at once |
|---|---|---|---:|---|---|
| **(a)** measured | 8 x 262,144 | `TF_FLASHNEXT_KV_PAGES=4096`, ask 6 GiB | **3,166 MiB (3.09 GiB)** `[M]`; the plan line prints `a 3.1 GiB prompt cache` | 4 / 1 / 1 / **0** | 8 streams; one 100k conversation, or a 100k one plus its two small states (2,226 MiB of 3,166 after turn 6 `[M]`) |
| **(b)** measured on the NVFP4 arm, derived on INT4 | 4 x 262,144 | off | **5.14 GiB** `[M]` (line prints `a 5.1 GiB prompt cache`); on the INT4 arm `[D]`: 31.0 - 4 x 4.99 = **11.0 GiB** | measured 5.14: 8 / 2 / 2 / **1**; derived 11.0: 17 / 5 / 4 / **2** | 4 streams; one full-window conversation (two would need 9.4 GiB) |
| **(c)** measured on the NVFP4 arm, derived on INT4 | 8 x 131,072 | off (optional at this window) | **3.66 GiB** `[M]` (line prints `a 3.6 GiB prompt cache`); on the INT4 arm `[D]`: room 33.31 - 8 x 2.68 = **11.87 GiB** | measured 3.66: 5 / 1 / 1 / **0**; derived 11.87: 18 / 6 / 4 / **2** | 8 streams; one 131k conversation, or five 32k ones at the measured figure |
| **(d)** production today | 8 x 262,144 | none (production's own plan) | **6,361 MiB (6.21 GiB)** `[M]`, production's own cache line | 9 / 3 / 2 / **1** `[D]`, with this lane's state sizes; in-RAM only, inside one boot | 8 streams; up to three 100k conversations while the boot lives |

The derived cells, spelled out:

- **(b) on INT4.** The INT4 room at 262,144 is 31.0 GiB `[M]`, from (a)'s line. With no pool the four streams'
  full windows come out of it: `31.0 - 4 x 4.99 = 11.04` GiB. `[D]`. The pool's planner can leave less than that
  arithmetic promises, which is exactly what (a) shows, so 11.0 GiB is an upper bound until that shape is booted.
- **(c) on INT4.** The engine's own window is inside the model's (4.99 GiB of the model's 69.39 GiB at 262,144
  `[M]`), so at 131,072 the model's own KV is 2.68 GiB and the room is `31.0 + (4.99 - 2.68) = 33.31` GiB `[D]`.
  Eight streams take `8 x 2.68 = 21.44`, so the cache is `33.31 - 21.44 = 11.87` GiB `[D]`.
- **(d) today.** Production's own launcher serves 8 at once at 262,144 with its own engine, no page pool, its own
  `sequence memory: 25.31 GiB (37.31 GiB free, 10.0 GiB kept free)` and `prompt cache: whole-prompt states from
  1024 tokens` (`work/DevVsProd/RESULT.md` section 2) `[M]`. Its cache line reads 6,361 MiB
  (`work/KvTierW4/RESULT.md` section 0) `[M]`. There is no disk tier, so nothing survives the boot.

## 4. What an appended agent turn gains, and what the shape loses

Measured appends, the tier on, at a 100k conversation (this window, `work/KvTierShip/RESULT.md` section 3): turn 6
**1.042 s** and 116.16 MiB, turn 7 **1.226 s** and 118.03 MiB, against their no-tier cold twins **44.206 s** and
**44.305 s** on identical prompts with identical token ids. That is 42 and 36 times less time to the first token,
and 0.9 to 2.5 percent more store bytes than the NVFP4 baseline's 115.1 MiB a turn. At 261k the tier's own measured
resume is 1.931 s against 127.854 s cold (`work/KvTierW4/RESULT.md` section 3, kill cell K3 against K4) `[M]`.

| shape | an appended turn gains | it loses |
|---|---|---|
| **(a)** 8 x 262,144, pool, 3.09 GiB | a 100k append resumes in **1.042 s / 1.226 s** and writes **116.16 / 118.03 MiB**, against 44.206 / 44.305 s cold `[M]`; decode is LEVEL at 1, 2, 4, 6 and 8 streams `[M]`; the shape keeps production's concurrency and window | the **full-window resume**: a 4.70 to 4.72 GiB state cannot fit 3.09 GiB, so a 261k conversation is never kept `[D]` (`prompt_cache_keep.zig:38` keeps nothing over the budget, and the log's own line is `kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget`), and its next turn pays the full cold prefill (127.854 s measured at 261k, `work/KvTierW4/RESULT.md` section 3) `[M]`; one 100k conversation fills the cache, so a second evicts the first `[D from 2,226 of 3,166]` |
| **(b)** 4 x 262,144, 5.14 GiB measured | the **full-window resume** fits: a 261k state resumes in **1.931 s against 127.854 s** cold `[M]`; a 100k append is the 1.04 s case `[M]`; two 100k conversations fit (5.14 / 1.87) `[D]` | **half the streams**: 4 at once instead of 8; only one full-window conversation (two need 9.4 GiB) `[D]`; at 4 streams the measured aggregate decode cells read 95.75 to 95.95 prose and 174.76 to 175.20 code tokens a second (`work/KvTierW4/RESULT.md` section 1) `[M]` |
| **(c)** 8 x 131,072, 3.66 GiB measured | several states fit at agent sizes: **5 x 32k** (0.635 GiB each) at the measured 3.66 GiB, and one 131k state; 8 streams stay; decode LEVEL in all 60 cells window 4 ran at 131,072, eight slots busy `[M]` | the **window itself**: 131,072 tokens a stream, so a conversation past ~131k cannot be served at that shape at all; the full-window resume is gone by construction; two 131k states need 4.82 GiB and do not fit 3.66 `[D]`; a 131k resume's speed is not measured in this lane (a 100k resume is 1.04 s, a 261k one 1.93 s, so 1.1 to 1.5 s is the derived band) `[D]` |
| **(d)** production today | within one boot, production's own cache serves a warm 2k turn on a kept 100k conversation in **1.123 s** mean (1.254 / 1.074 / 1.041 s, `work/DevVsProd/RESULT.md` section 4, measured on production only) `[M]` | **nothing across a boot**: every fresh-boot append is a full prefill, measured at 44.206 and 44.305 s at 100k in this window's twins `[M]` and 44.420 to 45.067 s across window 4's seven-turn agent shape `[M]`; a restart pays the prefill again, which is the case the tier exists for |

## 5. Which cells are measured and which are arithmetic

| figure | measured | arithmetic | source |
|---|---|---|---|
| (a) cache 3,166 MiB | yes | no | the store's own line, this window's `levels/on` and turn 6 records |
| (a) plan line 278 pages, 20.02 GiB, 31.0 GiB room | yes | no | this window's boot line, both level arms |
| (b) cache 5.14 GiB, 4 x 4.99 GiB, 25.1 GiB room | yes, NVFP4 arm | 25.1 - 19.96 = 5.14 | `work/KvTierW4/RESULT.md` section 0 |
| (b) cache 11.0 GiB | no | yes | 31.0 - 4 x 4.99 |
| (c) cache 3.66 GiB, 8 x 2.68 GiB | yes, NVFP4 arm | 25.1 - 21.44 = 3.66 | `work/KvTierW4/RESULT.md` section 0 |
| (c) cache 11.87 GiB | no | yes | 33.31 - 8 x 2.68, room 33.31 = 31.0 + (4.99 - 2.68) |
| (d) cache 6,361 MiB, 25.31 GiB sequence memory | yes | no | `work/KvTierW4/RESULT.md` section 0, `work/DevVsProd/RESULT.md` section 2 |
| state sizes 0.63 / 1.87 / 4.70 / 4.72 GiB | yes | rows + 110.28 MiB fixed at the window | `work/KvTierW4/RESULT.md` sections 3 and 5, `work/KvTierW5/RESULT.md` section 1 |
| appends 1.042 / 1.226 s and 116.16 / 118.03 MiB, twins 44.206 / 44.305 s | yes | no | `work/KvTierShip/RESULT.md` sections 3 and 4 |
| 261k resume 1.931 s against 127.854 s | yes | no | `work/KvTierW4/RESULT.md` section 3 |
| warm 2k turn 1.123 s on production | yes | no | `work/DevVsProd/RESULT.md` section 4 |
| capacity counts | no | yes | `floor(cache / state)` |

Unmeasured, and named so no one reads them as proved: the INT4 arm booted at (b) and (c); the pool switched on at
131,072; a 131k resume's own TTFT; an appended turn at 32k on this arm. Each needs its own window before it is
written into `env/dev.env`.
