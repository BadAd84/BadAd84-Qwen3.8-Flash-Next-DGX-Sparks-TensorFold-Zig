# Provenance of this package

- **What it is:** upstream pull request `ashhart/TensorFold#2815`, "flashnext cuda: hold two graphs per window graph
  cache slot", carried to measure it on a GB10. It is not ours.
- **Source:** `https://github.com/ashhart/TensorFold`, `refs/pull/2815/head`, commit
  `8cb59625d3100d9c27a4ad48c44ff48cccb83026` (author ashhart, committed 2026-11-10T23:37:05Z), one commit on merge
  base `fb8fdf3d8` (87 commits past v1.2.6). Fetched 2026-11-12, upstream main then at `000b534a2`.
- **Text:** `git format-patch -1` of that commit, verbatim. Not edited.
- **Base it applies to here:** v1.2.6 (`6e9af930261a88bb28ac0bfb157ce8e57e9eea07`), alone or after any prefix of
  `patches/1.2.6` (checked with a scratch index after 0, 7 and 13 of our patches).
- **Why it is here:** the PR's own body lists the GB10 run as still to do (Flash Next FP4-Local on one GB10, graphs
  on, one and four streams). Our round log has the window graph costing what eager launches cost at one stream
  (49.8 against 49.2 ms a prose forward), which is what a slot re-recorded on 57% of passes would give.
