# P5Gpu CLOSED: the prefill-tail window, cancelled by the lever's own decision

Status: CLOSED on 2026-11-21. The lever was dropped after its first receipts for having no measured benefit (upstream's
rule: a switch arrives with a measured benefit, and the earlier `work/upsubmit/P5Receipt` window was exact and level,
never faster). No further window was queued. Branch `flashnext-prefill-tail-up` stays local at
`e0f33b5a823e6cbbb9cbeea4d23831f94dfeda20`, un-PR'd.

## What ran

- Attempt 1 stopped at the argument check on my own harness defect (an expanded assignment list in `argcheck.sh`,
  fixed and proved with a stub; evidence `out/attempt1` in the fetched copy is not kept separately, the fix's proof is
  in `NOTES.md`).
- Attempt 2 reached `DONE` at 2026-11-21T00:24:36Z and restored production (`RESTORE prod_rc 0 /health 200` at
  00:26:08Z), but **pass A produced no cells at all**: all six decode arms (`M1 B0a B1a B1b B0b M2`) ended
  `ARM-FAILED after 2 attempts`.
- Cause: a foreign `start.sh` ran while this window held the lock (another lane's production launcher; its
  `prod-restart3.out` is stamped 23:29:14Z). `M1`'s attempt 1 booted (`ENVCHECK dev 7/7`, `Server answered after 36s`)
  but its probes failed at 23:28:39Z, and every later boot died in 0.01 s with `[start.sh] ERROR: another ./start.sh is
  already running; wait for it to finish`.
- Pass B kept only `MC2 B0C2 B1C1 B1C2`; `MC1` and `B0C1` failed the same way. Pass C and pass K ran in full.

## What is usable, and what is not

- Decode: nothing. Six arms failed, so there is no decode cell, no tokens-a-round row and no verdict.
- Cold cells, from `box/out/run/cold.md` (seconds to first token, one request a cell; the verdict columns are `-`
  because the pairs are incomplete, so these are measurements without a comparison):
  cold2k 0.955 (MC2) / 0.952 (B0C2) / 0.998 (B1C1) / 0.947 (B1C2); cold8k 3.676 / 3.696 / 3.757 / 3.640;
  cold32k 14.933 / 14.995 / 14.941 / 14.914; cold64k 30.659 / 30.705 / 30.600 / 30.516; first ttft 1.144 / 1.145 /
  1.149 / 1.138. They sit within about 1% of each other, which agrees with the earlier window's level result.
- Boundary prompts: cells exist for those four arms with `12 equal, 0 unequal` on the comparisons that could run.
- Pass C (six boots) and pass K (six boots): every one booted with `ENVCHECK dev 7/7` and `foreign 0`, so their
  contracts and key rows were taken on clean arms; the key table read `Controls 2 of 2 restored`. Both are moot now
  that the lever is dropped, and the key table's witness pairing collapsed because the store wrote no files to disk
  (`KDISK ... files_before 0 files_after 0`), so no cross-switch witness was measured.

## Evidence and cleanup

- Evidence: `work/P5Gpu/box/` (fetched by Main). Before deletion the box's copies matched byte for byte:
  `run.log` `57d6290d22842ed8866ac61f55f2af40a6560c764370f7c224100a94169191eb`, `build.out`
  `f811b75963dcbe7c921f8698c588764468e25997abd5f28b4f98c2026f04fefe`, `argcheck.log`
  `f10bd6e8a7c6410b33db229a829bceb708d90856232d5fe0dd8e59514191a941`.
- Box cleanup: `docker rmi tensorfold-qwen38:p5-m-124052c9 tensorfold-qwen38:p5-b-e0f33b5a` (digests d9d4a02b75a1 and
  bcc551e28730) and `rm -rf /home/adam/work/P5Gpu`, verified (`no p5 images`, scratch gone); `~/INVENTORY.md` records
  the closure; the key cell left no `p5key` directory; no flock waiter or driver of this lane remains; sparkDash was
  not touched by this lane.

## Production line after the closure, read twice

Measured by this lane at 2026-11-21T02:10:42Z, one ssh: `docker inspect qwen38-flash-next-tf` reads
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
StartedAt 2026-11-21T02:07:26.078089174Z`, `curl /health` returns `200`, `docker images | grep p5-` returns nothing (so
no p5 tag can win a later restore), `~/work/P5Gpu` is gone, no `P5G_LOCKED` process of this lane exists, and the only
waiter on `~/work/gpu.lock` is SyncBench's `run_sync.sh` (pid 2362210). SyncBench's own reading at 02:10:28Z agrees on
the same tag, id and code; the serve is on the owner's image by that lane's EXIT-trap restore.
