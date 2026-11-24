# `PrefillKernelPort`: the 0041 prompt-tile window

- `MECHANISM.md` - the mechanism map: production's captured `_b16mm_ks`/`_fp4mm_ks`, what the dev engine already
  runs, the three tile constants that differ, why the dev refuses a captured set at fp8 KV, and the route decision.
- `AB-PLAN.md` - the next free GPU window's arms, cells, commands and the comparison that confirms or refutes the
  `+0.31 s`/`+1.31 s` expectation.
- `driver/` - the window harness: `boot_env.sh` (arms F0/F1/F2), `window.sh` (the lock, boots, cells, restore),
  `score_pks.py` (the tables), and the ParityGap `hash_cmp.py`/`rounds.py` reused unchanged.

No window is queued: spark6's GPU is saturated (a confirm window runs and two sessions' windows are queued behind
it). When a window frees, the commands are in `AB-PLAN.md`.
