# Open TensorFold PRs vs the recipe's 17 patches and our levers (2026-11-08)

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
