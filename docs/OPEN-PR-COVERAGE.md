# Open TensorFold PRs vs our levers

## 2026-11-12: 278 open, 40 about Flash Next or Qwen3.8, and main has moved

Read with `gh pr list -R ashhart/TensorFold` (278 open) and a fetch of upstream main, `000b534a2`
(2026-11-12T02:11Z). The scan below this section (2026-11-08, 199 open) is kept as it was.

**Upstream has moved under our base.** v1.2.7 was tagged 2026-11-11 (`93a2e93ec`, 188 commits past v1.2.6) and main
is 120 past that. 23 of the 308 commits touch Flash Next, the lane core or the lane tile. By title the CUDA ones are
checks and refusals (`dfd9ac5ef` malformed settings refused by name, `c6a337753` verify rows checked after one wait,
`80e0fd72c` non-finite selections, `ab2d08ac3` chunk invariance under `--decode-share`, `37b0776ce` one sampled
rule, `e32de56c6` qmmf's FP4 decode behind a build flag); none is titled as a one-GPU decode speed change. Our 13
patches apply on v1.2.6 only: on v1.2.7 the first stops in `CHANGELOG.md`, on main in `CHANGELOG.md`,
`cuda_lanes_load.zig`, `cuda_mtp_draft.zig` and `platform/environment.zig`. The repo rule for a version bump
(re-seat, re-test every patch, retire what upstream absorbed) is due.

**The 40, by what they are:**

| group | PRs | bearing on the one-GPU NVFP4 serve |
|---|---|---|
| Flash Next on CUDA, one GPU | #2815 two graphs a window-graph slot; #2927 sampled draws in one launch and one wait a step; #2898 pool lanes as pieces on any pages; #2763 KV in the display carveout (draft) | #2815 is carried and queued (below). #2927 is exact and aimed at sampled streams, which is what the recipe serves by default (temperature 1.0) and what our greedy benchmark does not exercise; as cut it conflicts with main and does not apply on v1.2.6. #2898 and #2763 are capacity, not speed |
| Flash Next on CUDA at `--tp 2` | #2837, #2969, #2971, #2972, #2976, #2977, #2978, #2980, #2982 | two-rank work; window graphs are off at TP=2 |
| EXL3 Flash Next | #1441 to #1446, #1522 (20k to 49k lines each) | another checkpoint format |
| Flash Next on HIP (AMD) | #1878, #2695, #2696, #2697, #2728, #2730 | another backend; what they add (parked gather workers, batched heads, wider windows) the CUDA path has, and #2697 is a confidence default |
| Flash Next on Metal | #2805 | another backend |
| Qwen3.8-27B (the dense model, family `qwen3_5`) | #1835, #2000, #2023, #2078, #2464, #2634, #2648, #2799, #2854, #2895, #2921 | not Flash Next |
| shared cleanups | #2392, #2679 | none |

Outside the 40 but touching us:

- **#2266** (NVFP4 routed experts through a per-warp `cp.async` ring, +24% on GLM at sm_120): the experts are 29% of
  our round (18.1 of 62.6 ms), but the PR keeps GB10 on its register form and reports the sm_121 SASS byte-identical
  to main's for all 19 expert functions, with its GB10 cells level. It does nothing for us as it stands.
- **#2687** (the lane core prices plain shared rounds apart from drafted rows): the same ground as our round-cost
  patch (0010), from the core's side. If it lands, 0010 is re-tested against it first.
- **#2934** (`qwen3_5`: windows of 2 to 8 rows run at 4 and 8 rows, not 16): an idea, not a patch for this family.
  Our verify windows are 5 to 7 rows on the lane's 16-row tile; whether Flash Next pays for the padding is unchecked.

**#2815, carried:** `upstream/tensorfold-pr-2815/` (the commit `8cb59625d` as `git format-patch` wrote it, with
`RECORD.md`). It applies untouched on v1.2.6 alone and after 7 or all 13 of our patches. Its body says a window slot
re-records its graph on 57% of passes and lists the GB10 run as still to do. Our round log agrees with the symptom:
on the accepted rung the window graph costs what eager launches cost (49.8 against 49.2 ms a prose forward).
`pr2815.sh` runs it against the accepted rung at one and four streams with the engine's own capture counts.

## 2026-11-08: the recipe's 17 patches and our two levers (199 open)

Checked: all 199 open PRs' titles against the 17 feature keywords, plus diff-level file checks on the 9
candidates that matched (2593, 2585, 2577, 2576, 2528, 2568, 2507, 2266, 1394 - all opened 2026-10-26 to
2026-11-08, none older). Diffs taken against `267c5af6a` (the tip our arms ran).

## Verdict

**No open PR covers any of the recipe's 17 patches, nor our two levers.** The Flash Next work in open
PRs is: #2593 (6/8-bit row products on Metal-class simdgroups - Metal, not CUDA), #2585 (strict
`TF_FLASHNEXT_*` validation - no overlap with our settings, 0 code-file mentions of copy_resync/warm_turns),
#2577 (window-graph key hashing - a bugfix on #2444's KV-pool work), #2266 (NVFP4 expert decode via a
cp.async ring, GLM-5.3), #2507 (sampled top-k skipping doomed blocks), #2576/#2528/#2568 (HIP + KV-pool
items). The recipe's features - fp8 KV for Flash Next, copy windows, the resync, 64/48-row windows, the
expert tiles, hc fusion, mx128 prompt tiles, host draws, contract_controls, the vision loader, the
prompt-hc fusion - appear in no open PR title or diff.

## The near-misses

- **#2576** "the 64-row routed tile reads the prompt chunk's rows, so its 1,024-row cap holds" - HIP
  (ROCm), a routed-experts tile cap, not the Flash Next copy-window invariance on CUDA. Different backend,
  different mechanism.
- **#2528/#2568/#2577** - the KV-pool chain (#2444): a lane host a pool, reclaim hooks, window-graph keys.
  Adjacent to the pool-of-kept-graphs lever but not it (those are KV pages, not captured decode graphs).
- **#2266** - NVFP4 expert decode via a per-warp cp.async ring, same bits, GLM-5.3 83.8 -> 104.1 tok/s.
  If it generalises to Flash Next's NVFP4 experts it would stack with our levers; its title scopes to GLM.
- **#2585** - strict `TF_FLASHNEXT_*` validation. Complementary to everything of ours (we rely on strict
  settings too); 0 code mentions of our settings.

## The 12-bit read-out check

#2593 "6- and 8-bit row products take 2 outputs a simdgroup" is Metal simdgroup work, not the CUDA hc
read-out path our lever changed - and our lever measured flat on 1.2.4 anyway, so nothing to check there.

## Implication

The recipe's 17 patches remain a genuine porting backlog: nobody upstream has submitted any of them
against the 1.2.4 kernel layout. Our 0064/0065 are the only two features from the whole campaign that
exist as reviewable diffs against upstream 1.2.4, alongside the maintainer's own merged work
(confidence handling, KV-pool pages, KEEP_LATE, lane-batched DeltaNet, staged copies, first-token
sooner).
