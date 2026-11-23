# Provenance of this package

- **What it is:** one line of the recipe's `start.sh`. The environment-forwarding filter is
  `'^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+='`, so every setting the engine's own table declares with the bare `TF_`
  prefix is dropped before `docker run`: 26 of the 95 rows on the served tree (`TF_CACHE_EVICT`, `TF_MTP_DRAFTS`,
  `TF_CUDA_DEVICE`/`SEGMENTS`/`CARVEOUT` and the rest, `zig/src/platform/environment.zig`). A stated value for any of
  them cannot reach the container, so the environment of record is undeliverable for 26 names.
- **Source:** `https://github.com/MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold`, commit
  `20e15e41f2f514a0d287710f4665ee1b5009ba41`, file `start.sh` at line 173. The same line is carried by the two
  `start-nsys-ours*.sh` copies in that tree, which are ours rather than upstream's, and by our own deployed
  launcher `~/qwen-zig/start.sh:172` on spark6 (four files, one line each).
- **Text:** a hand diff of that one line, ours. `TF_FLASHNEXT` is a `TF_` name, so the wider class covers the two
  prefixes the filter already passed.
- **Base it applies to here:** the recipe at `20e15e41` (`start.sh` unmodified, `git status --short start.sh` clean).
- **Status: PROPOSED, STATICALLY PROVED NEUTRAL, BOOT A/B QUEUED, NOT POSTED.** The first proof is done and tracked
  at `docs/receipts/EnvForward/TABLE.md`: of the 27 statements (26 exports and one `unset`), 11 are EQUAL to what
  absence yields (the live one is `TF_QMMF_HALF_BELOW`, 96, the `half_below_default` at `cuda/qmmf.zig:121`),
  16 are INERT (their only readers are in `families/qwen3_5/` or absent from this tree), and 0 DIFFER, so the
  widened filter is behaviour-neutral for the flashnext TP=1 serve. The second proof is a boot identity window,
  `work/LauncherAB/window.sh`, queued on spark6 behind the existing GPU queue: it boots the widened launcher with
  the same image, env and shape as DevEnvBoot, requires all 26 names in the container at their stated values,
  the window self-check at 1176 of 1176, and the fixed-prompt reply hashes equal to DevEnvBoot's, then restores
  production and runs the production env drift check.
- **Why it matters beyond the file:** the engine reads these names, so a serve that intends to set one today silently
  runs its default. The environment register's rule is that every setting is stated and deliverable; without this
  line 26 of them are neither.
