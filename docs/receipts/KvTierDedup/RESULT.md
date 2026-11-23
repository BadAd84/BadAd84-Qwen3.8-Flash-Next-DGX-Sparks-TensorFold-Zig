# KvTierDedup: the append dedup, gated and measured

Window 5 proved the NVMe KV tier's equal-depth exactness and attributed the append write amplification: on a fresh
boot the rewind keep is decided by `keptNear` (`core/prompt_cache.zig`), which scans the RAM store only, BEFORE
`rows.read.recall` reads a disk state back, so the state the pass is about to resume from is invisible and a second,
nearly identical state is written beside the endpoint (227.5 MiB a turn against 116.3 MiB for the boundary-only
shape, `work/KvTierW5/RESULT.md` section 2). This lane lands the fix as `0022-kv-tier-dedup.patch` on top of
`0021`, pins it with a host test that fails before and passes after, gates it on Paperclip, and measures it on
spark6 against the `kv-w1` image on the same conversation.

**Headline, measured on spark6 in one GPU-lock hold:**

- **Bytes a turn after the fix: 115.1 MiB** (120,652,172 B, mean of the four deduped appends, turns 6, 8, 9 and
  10 - the turns whose previous reply is under 256 tokens), against **228.1 MiB** (239,147,228 B) for the same four
  turns on `kv-w1` (0021) and the recorded **227.5 MiB** baseline. Ratio 0.50: the append's bytes are halved for
  replies under 256 tokens, and only there - a turn after a reply of 256 tokens or more writes 231.2 MiB on both
  arms (next paragraph, and turn 7 in the table below).
- **TTFT: 1.032 s** at the recorded depth (resumed at 105,202, prefill 0.327 s) against the recorded M1b
  **1.068 s / 0.358 s** and the same-depth `kv-w1` boot's 1.102 s / 0.399 s. The no-tier cold twin of the same
  prompt is 46.716 s.
- **Exactness: five of five pairs equal.** Every resumed reply's token ids equal its no-tier cold twin's, and the
  two arms' replies are identical to each other, at 320, 32, 32, 29 and 19 generated tokens (sha16
  `277412fd297b56aa`, `af913cc499e378a6`, `1b6cdb6c046cd2c6`, `fadbe9183c3f5d09`, `505b2cc22424a0d7`).
- **A 60 GiB budget now holds 508 append turns** (was 257) when every reply is under 256 tokens, and a 100-turn 100k
  conversation of that shape writes 14.1 GiB (was 25.0 GiB). The bound is the short-reply shape: replies of 256
  tokens or more double the write (231.2 MiB a turn, 253 turns in 60 GiB; section 7). A real agent turn's reply length
  decides which figure applies, and this lane measured only replies of 19 to 320 tokens.

The one shape where the bytes do NOT halve is the boundary the code names: when the previous turn's reply plus the
new user message is 256 tokens or more (`min_gap`), the rewind point is far enough from the resumed state that the
rewind state is genuinely useful, and both arms keep it. Measured on turn 7 after a 320-token reply: **231.2 MiB on
both arms** (242,454,924 B each), because there the fix correctly does nothing.

## 1. The change and the package

`patches/main-1ece6e6db-r5-kvtier/0022-kv-tier-dedup.patch`, cut against the 0021 tree, 2 files, +52 / -2:

    zig/src/core/prompt_cache.zig              +9  -2
    zig/src/core/prompt_cache_rewind_test.zig  +43 -0

The diff, in full (the code half):

```
+        const ram = s.find(prompt, starts, spans);
         const e = if (disk)
-            rows.read.recall(s, prompt, born, starts, spans, s.recall(prompt, born, starts, spans, s.find(prompt, starts, spans)))
+            rows.read.recall(s, prompt, born, starts, spans, s.recall(prompt, born, starts, spans, ram))
         else
-            s.find(prompt, starts, spans);
+            ram;
+        // a state recalled under min_gap before the rewind is the rewind state: no second copy (keptNear's rule)
+        if (e) |x| if (x != ram and x.at <= s.active_rewind_at and s.active_rewind_at - x.at < s.rules.min_gap) {
+            x.rewind = true;
+            s.active_rewind_at = x.at;
+            s.active_rewind_key = sharedKey(prompt[0 .. x.at + s.rules.lookahead]);
+        };
```

Why this shape, rather than clearing `active_rewind_at`:

- `x != ram` is the "a disk state was actually read" test. With no disk tier `s.recall` and `rows.read.recall`
  return the RAM `find` unchanged, so the condition cannot fire and the RAM rewind rule (`keptNear`, and the test
  that pins it) is untouched: the pre-existing rewind tests all pass unmodified.
- Re-pointing `active_rewind_at` and tagging `rewind` is exactly what `keptNear` does for a RAM state, so the
  resumed state is charged by `fittingRewind`/`interior`/`intermediate` and protected from eviction as the active
  rewind, and the rewind mark is dropped by the same `at <= from` filter a RAM-deduped rewind already is.
- The slice `prompt[0 .. x.at + lookahead]` is in bounds because `active_rewind_at > 0` implies the rewind itself
  passed `rewind + lookahead <= prompt.len`, and the condition guarantees `x.at <= active_rewind_at`.

The package carries the patch, its `SHA256SUMS` line, the `README.md`/`CHANGES.md`/`RECORD.md` sections, and
`apply.sh` is unchanged (it globs the directory, so 0021 then 0022 apply in filename order). `README.md`'s
`--check` line now reads "the series and 2 KV-tier patches apply on 1ece6e6dbb... in order (nothing written)".

## 2. The tree the package reproduces, and the 0021 control

- A fresh worktree at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` + `apply.sh` (the r5 series, then 0021 and 0022)
  produced a tree **file-for-file identical** to the gated `head` tree: 12,622 files each, `diff` of the sha256
  listings empty (`PATCH-REPRODUCES-HEAD`).
- The same worktree + the series and 0021 alone (`pre`) is **byte-identical to window 1's gated tree**
  (`work/KvTierW1/tree`, 12,622 files, 0 diff), so the lean base and the before/after test are the artifact window 1
  gated, not a re-seat.

## 3. The test, failing before and passing after

The test (in `prompt_cache_rewind_test.zig`) seeds one learned state on disk at 6 tokens, then boots a fresh store
over the same imprint with the conversation `sys ++ {1..8}`, a history of 13 and a rewind length of 9 (rewind point
8, `min_gap` 4). The recall resumes at 6, two tokens under the rewind, and the plan must keep the endpoint alone.

Before (the 0021 code with only the new test copied in, `prefail`):

    GATE preflight-test (must fail before the change): zig build -Dfixed-cpu test-prompt-cache-host
    error: 'prompt_cache_rewind_test.test.a state recalled from disk under min_gap before the rewind is the rewind: one keep, no second copy' failed:
           slices differ. first difference occurs at index 0 (0x0)
           ============ expected this output: =============  len: 1 (0x1)
           [0]: 13
           ============= instead found this: ==============  len: 2 (0x2)
           [0]: 8
           [1]: 13
    Build Summary: 1/3 steps succeeded (1 failed); 706/707 tests passed (1 failed)
    GATE preflight-test rc 1
    GATE PREFail-OK preflight-test failed before the change

After (the same test on the 0022 tree):

    GATE prompt-cache: zig build -Dfixed-cpu test-prompt-cache-host
    GATE prompt-cache rc 0

The failure is the defect's own shape (`{8, 13}`: the endpoint and the rewind), not a compile error, and it is the
only failing test in 707 on the pre-change code, so the fix is load-bearing and the test discriminates.

## 4. The host gates (Paperclip, x86-64, Zig 0.17.0, `flock ~/work/host.lock`)

| gate | command | result |
|---|---|---|
| fmt | `zig fmt --check build.zig zig` | `GATE fmt rc 0` |
| before/after | `zig build -Dfixed-cpu test-prompt-cache-host` on `prefail` | `GATE preflight-test rc 1`, `PREFail-OK` |
| the cache's suite | `zig build -Dfixed-cpu test-prompt-cache-host` | `GATE prompt-cache rc 0` |
| the store's filtered suite | `zig build -Dfixed-cpu test-cache-store-host` | `GATE cache-store rc 0` |
| learned-state recovery | `zig build -Dfixed-cpu test-learn-recovery` | `GATE learn-recovery rc 0` |
| environment | `zig build -Dfixed-cpu test-environment-host` | `GATE env-host rc 0` |
| serving | `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | `GATE serving rc 0` |
| kept image | `zig build -Dfixed-cpu test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | `GATE kept rc 0` |
| kernel contract | `zig build -Dfixed-cpu test-kernel-contract` | `GATE contract rc 0` |
| cross-compile | `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | `GATE cross-config rc 0` |
| cross-compile | `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | `GATE cross-tests rc 0` |
| CUDA copies | `python3 tools/zig/cuda_common_check.py` | `cuda common: 55 local copies, 0 violations`, `GATE cuda-common rc 0` |
| CUDA fragments | `python3 tools/zig/cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses`, `GATE cuda-fragment rc 0` |
| pins | `python3 pincheck.py head/` | `files 170 failing 0`, `GATE pincheck rc 0` |
| lean pair | each tree's own `lean_check.py`, then `lean_new.py` | base `7014 files, 230 problems`; head `7014 files, 230 problems`; `lean: 230 problems, 230 on the base, 0 new`, `GATE lean-new rc 0` |
| lean control | `pre`'s copy run from `head/` | `7014 files, 230 problems` (each tool scanned its own root) |
| the umbrella | `zig build -Dfixed-cpu test` | `GATE suite rc 0` |

Every gate ran on freshly extracted trees from the staged tarballs (sha256 verified both ways:
head `73e9e271...`, pre `c71a7c81...`). The gate log is `ev/gates-ev.tgz` (sha256
`2acedc28af3962780e86c7f0a98440e3e7531d39f435a3430b6e4911423ce7ea`).

One reading note, recorded rather than hidden: the log carries `failed command:` lines inside steps whose rc is 0
(e.g. between `GATE preflight-test rc 1` and `GATE prompt-cache`, and inside `prompt-cache`, `learn-recovery` and
`contract`). Those are output interleaved from child processes of the test runs; the authoritative verdict is each
step's rc, and every step's rc is quoted above. The contract step, for instance, printed two such lines and
returned `GATE contract rc 0`.

## 5. The device window (spark6, one GPU-lock hold)

Image built on the box from the gated tree: `tensorfold-qwen38:kv-dedup`,
`sha256:2f0f1c5a7d0492679f56fd06eb4884a21d92baf42f6568eb25af37d05cb96b9f`, labels `tf.patches 4144696f21e3`,
`tf.kernels embedded` (the docker build's step #10 took 479.7 s). The baseline arm is
`tensorfold-qwen38:kv-w1` (`sha256:ef6967ac...`, window 1's image). Both booted the NVFP4 checkpoint, fp8 KV, one
slot at a 262,144-token window, `--dashboard`, and the four store flags
(`--prompt-cache-disk --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20`), with production's own 53
`TENSORFOLD_`/`TF_FLASHNEXT_`/`KV_` environment read from its container and the INT4 MTP overlay removed (the tier
images take the NVFP4 checkpoint).

The conversation is window 5's: 100,000 words in the system message, turns 1 and 2 short, turns 3 to 5 distinct
1,200-word passages, then five append turns whose replies are counts. The seed (turns 1 to 5 in ONE boot, 32-token
replies) writes 3,168,781,592 B (2.95 GiB) on both arms, and its five prompts are the lengths window 5's reference
arm recorded (100,040; 100,099; 101,800; 103,505; 105,209 tokens, `work/KvTierW5/tables.md`'s reference turns) with
three of its reply hashes equal to the ones quoted there (`052beccc2fc3c430`, `81adacd4eeead45c`,
`b732c5c07f27d37a`), so the conversation and the engine are the same as the recorded baseline. Each append is its
own fresh boot on the arm's store, one greedy request, and the store's own file set read before and after.

Turn 6 is the direct comparison with the baseline: the same prompt as window 5's X1 (105,279 tokens), resumed from
the same state at 105,202.

| arm | turn | prompt tokens | resumed at | TTFT s | prefill s | kept | states added | added bytes | MiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| new | 6 | 105,279 | 105,202 | 1.032 | 0.327 | 1 | 1 | 121,954,256 | 116.3 |
| new | 7 | 105,639 | 105,272 | 1.297 | 0.576 | 2 | 2 | 242,454,924 | 231.2 |
| new | 8 | 105,712 | 105,632 | 1.049 | 0.330 | 1 | 1 | 120,463,540 | 114.9 |
| new | 9 | 105,785 | 105,705 | 1.035 | 0.320 | 1 | 1 | 121,841,336 | 116.2 |
| new | 10 | 105,856 | 105,778 | 1.068 | 0.332 | 1 | 1 | 118,349,556 | 112.9 |
| old | 6 | 105,279 | 105,202 | 1.102 | 0.399 | 2 | 2 | 238,564,436 | 227.5 |
| old | 7 | 105,639 | 105,272 | 1.245 | 0.540 | 2 | 2 | 242,454,924 | 231.2 |
| old | 8 | 105,712 | 105,632 | 1.084 | 0.382 | 2 | 2 | 240,358,896 | 229.2 |
| old | 9 | 105,785 | 105,705 | 1.099 | 0.394 | 2 | 2 | 238,263,060 | 227.2 |
| old | 10 | 105,856 | 105,778 | 1.126 | 0.407 | 2 | 2 | 236,094,824 | 225.2 |

`kept` is the prompt pass's own report line ("prompt cache: N tokens, resumed at M, kept K"), `states added` is the
store's `.st` delta across the boot and `added bytes` the `.st` plus `.blk` delta. The writer's own lines name the
files:

- new t6: `imprint: 105272 tokens on disk: 1 new blocks and its own 111 MiB (116 MiB this state, 1894 MiB of rows it
  shares) in 156 ms` (one write);
- old t6: the same 105,272 line, then `imprint: 105245 tokens on disk: 0 new blocks and its own 111 MiB (111 MiB
  this state, 1894 MiB of rows it shares) in 165 ms` (the second state, the rewind 27 tokens under the endpoint);
- new t7: `105632 ... 113 MiB` and `105603 ... 113 MiB`: the rewind at 105,603 sits 331 tokens above the resume at
  105,272, over `min_gap` (256), so the rewind state is kept by both arms and the two rows' bytes are identical.

Old t6's 238,564,436 B is window 5's X1 figure to the byte (227.5 MiB), which is the baseline this window set out
to halve. New t6's 121,954,256 B is window 5's M1b figure to the byte (116.3 MiB): the code change reproduces the
boundary-only mitigation's write shape without the budget that refuses the second state.

## 6. Exactness

Five resumed replies against five no-tier cold twins of the same messages files:

| turn | prompt tokens (both) | ids equal | ids sha16 |
|---:|---:|---|---|
| 6 | 105,279 | yes | 277412fd297b56aa |
| 7 | 105,639 | yes | af913cc499e378a6 |
| 8 | 105,712 | yes | 1b6cdb6c046cd2c6 |
| 9 | 105,785 | yes | fadbe9183c3f5d09 |
| 10 | 105,856 | yes | 505b2cc22424a0d7 |

Each twin is a fresh boot of the same image with no `--prompt-cache-disk`, the same messages file and the same
320/32-token cap; its cold prefills ran 46.7 to 47.4 s. The two arms' replies are equal to each other on all five
turns as well, so the fix is a write-side change only: same resume depth, same reply, same prompt tokens.

Turn 6's sha16 `277412fd297b56aa` is also the cold-twin hash window 5 recorded for this conversation's turn 6
(`work/KvTierW5/RESULT.md` section 1.3), so the exactness verdict is anchored to the recorded baseline as well as
to this window's own twins.

## 7. Disk arithmetic after the fix

From the measured deltas (per-shape means; a 100-turn session is the seed plus 99 appends; turns in 60 GiB is
`(60 GiB - seed) / bytes a turn + 1`):

| shape | turns | bytes an append turn | MiB a turn | 100-turn session | turns in 60 GiB |
|---|---:|---:|---:|---:|---:|
| new, one state a turn (the dedup) | 6, 8, 9, 10 | 120,652,172 | 115.1 | 14.1 GiB | 508 |
| new, two states (the 256-token boundary) | 7 | 242,454,924 | 231.2 | 25.3 GiB | 253 |
| old, two states a turn (0021) | 6 to 10 | 239,147,228 | 228.1 | 25.0 GiB | 257 |

The seed is 3,168,781,592 B on both arms. So an agent session (a boot per turn, short replies) that held 257
turns under the 60 GiB cap now holds **508**, and its 100-turn 100k conversation costs **14.1 GiB instead of
25.0 GiB**. Under the 200 GiB daily ledger the append count goes from 884 to about 1,754 a day. A turn whose
previous reply is 256 tokens or longer stays at the two-state shape (231.2 MiB measured), which is the boundary the
`min_gap` condition names, not a defect: there the rewind state really does sit far enough from the resume to serve
a later edit.

## 8. Disk discipline and production

- `/home` on spark6 read 111 GiB free at the lane's pre-window probe (production up) and 125 GiB at `DISK-START`
  (production stopped); the window's own stores were 3,893,845,204 B (new arm) and 4,364,517,732 B (old arm), 7.69 GiB
  together, written on top of the seed's 2.95 GiB a side. The store roots and the scratch (a 40 MB tree tarball, a
  40 MB build context, 12 MB of evidence) were removed; `df -Pm` read 119 GiB free at the restore line and 129,549 MiB
  (126.5 GiB) after the cleanup, and the removals are verified: `/k/kvd` gone, no `.part` file under `/cache`,
  `~/work/KvTierDedup` gone.
- The image `tensorfold-qwen38:kv-dedup` (`sha256:2f0f1c5a7d04...`) is KEPT for a re-measurement of this window;
  `~/INVENTORY.md` records it with `docker rmi tensorfold-qwen38:kv-dedup` as its removal.
- Production was restored by the window's `EXIT` trap:

      RESTORE prod_rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 id sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
      PROD-IMAGE-OK sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f

  and read back afterwards: the pinned id, `running`, `/health` 200.

## 9. Void passes and scope

- **Void pass 1 (04:50 to 04:51):** the first launch was stopped by me within a minute of starting the image build.
  Its plan had three append turns each with a 320-token reply, which puts the next turn's rewind point 320+ tokens
  above the resumed state, beyond `min_gap`: only turn 6 would have deduped, and the window would have measured a
  mixed shape without saying why. The design was changed to short replies between the two 320-token turns (6 and 9)
  and re-launched; the aborted pass wrote no store state, and its `FAIL image build` lines are the ones the second
  pass's log still carries above `IMAGE-BUILD start 04:53:17`.
- **Scope:** one conversation, one template, fp8 KV, the NVFP4 checkpoint, one slot at a 262,144-token window,
  replies of 320, 32, 32, 29 and 19 greedy tokens. Not tested here: bf16 KV, the INT4-AutoRound checkpoint (the
  prerequisite window 4 recorded), multi-slot boots, and a reply long enough to flip a late argmax. The host test
  pins the plan (one keep) rather than a store write, because the cache's shape has the plan decide the writes and
  the device measurement is the write-side witness.

## 10. Reproducing this lane

Payload is `work/KvTierDedup/payload` (`SHA256SUMS` inside): `run.sh` (stages `image`, `new`, `twins`, `old`,
`analyse`, `clean`, `all`), `kvdlib.sh` (boot, restore, store operations, evidence), `kvdconv.py` (the
conversation), `kvdreq.py` (one request plus the `/v1/imprint/resume` probe), `stls.sh` (the store's own file set
from its trailers), `kvdanalyse.py` (the tables) and `build_image.sh` (the recipe's Zig image from a tree tarball);
`setup.sh` and `gates.sh` (the host's tree extraction and gate list) sit beside the payload directory.

    # host: extract the trees, then the gates (Paperclip)
    bash setup.sh && bash gates.sh                      # under flock ~/work/host.lock
    # device: build the image, then the window from scratch
    bash payload/run.sh all                             # self-locks ~/work/gpu.lock, restores production on exit
    # the device run in this lane, exactly:
    ssh spark6 'cd ~/work/KvTierDedup && flock -o -w 43200 ~/work/gpu.lock bash payload/run.sh all'

Evidence: `work/KvTierDedup/ev.tgz` (device: `out/window.log`, `out/tables.md`, every boot's log and record, the
store listings; sha256 `8fb7ea2729e0bf99274a7b538c2ab519c9e0eeb74067a3df3e89751cfd8c3541`) and
`work/KvTierDedup/ev/gates-ev.tgz` (host gate log; sha256
`2acedc28af3962780e86c7f0a98440e3e7531d39f435a3430b6e4911423ce7ea`). The gated image is
`sha256:2f0f1c5a7d0492679f56fd06eb4884a21d92baf42f6568eb25af37d05cb96b9f`.
