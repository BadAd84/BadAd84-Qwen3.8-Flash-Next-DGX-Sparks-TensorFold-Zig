# Levers upstream has absorbed (hunk level)

No patch of `patches/main-964174ea05` is wholly retired on `1ece6e6db`: two patches each held a second lever that no
upstream commit implements, so both were re-seated in reduced form. What was dropped, and the commit that carries the
same behaviour on main:

| from patch | hunk retired | upstream commit | PR | evidence on `1ece6e6db` |
|---|---|---|---|---|
| 0005 | `default_chunk` 1,536 -> 3,072 in `cuda_batch_state.zig`, its startup check in `cuda_startup_test.zig`, and the scratch-bound test in `cuda_batch.zig` | `e172bcc29` "perf(flashnext): a prompt pass holds 3,072 rows by default" | #3726 (merged 2026-11-19T22:50:19Z, merge `bc99bab7b`) | `cuda_batch_state.zig` reads `pub const default_chunk: usize = 3072;`; `cuda_startup_test.zig` checks `3072`; `cuda_batch.zig`'s test is "a pass's scratch at the default chunk stays under three gigabytes" with `< 3 << 30` |
| 0008 | the fused prompt read-out: `flashnext_hcn.cu` (486 added lines), `flashnext_hcn` fatbin and blob entries, `cuda_tile_kernels.zig`'s hcn tiles, `cuda_tiles.zig`'s `nativeFused`/`readoutFused`/`pickDown`, `cuda_batch_hc.zig`'s `promptFused`/`writeback`/`mlpWriteback`/`readout`, the HC2 knobs (`TF_FLASHNEXT_PROMPT_HC2`, `TF_FLASHNEXT_HC2_MIN`, `_DN`, `_UP`), their environment rows, and the `hc-fuse` test | `12233bee5` "flashnext cuda: TF_FLASHNEXT_READOUT_FUSED, a prompt pass's BF16 read-out on two fused tiles", refined by `7358f5c4f` | #3413 (merged 2026-11-20T11:10:34Z, merge `9748adc7e`) | `readout_fused.zig` reads `TF_FLASHNEXT_READOUT_FUSED`; `cuda_tiles.zig` has `fused_rows`, `nativeFused`, `pickDown`, `fusedDown`, `fusedUpMix`, `readoutFused` |

What each reduced patch still carries:

- **0005** (`0005-prompt-sync-mx128.patch`): the prompt pass's missing drain on one rank (`TF_FLASHNEXT_PROMPT_SYNC`)
  and the relaxed MX128 prompt tile (`TF_FLASHNEXT_PROMPT_MX128`), with its kernels and `0006`'s two-stage variant
  building on it. Main still carries `if (hooks.logits == .none) try e.complete();` in `cuda_prompt.zig` (drain every
  non-final chunk) and no `prompt_mx` kernel in `qmmf.cu`.
- **0008** (`0008-shared-direct-head-piece.patch`): the shared-direct MoE write-back
  (`TF_FLASHNEXT_PROMPT_SHARED_DIRECT`, with `fn_hc_writeback_moe_sh` in `flashnext_hc.cu` and the `mode 3` glue arm)
  and the head-piece cap (`TF_FLASHNEXT_HEAD_PIECE`). Main has neither name.

Nothing else of the 19 is absorbed on `1ece6e6db`: the markers of 0001 to 0019 are absent from main except where the
two rows above say otherwise (`RECORD.md` has the per-patch verdict), and `git log -S<marker>` over
`964174ea05..1ece6e6db` finds no commit that added a marker and later removed it.

## Absorbed on main after this base: retire at the next re-seat, do not re-add

Four more units have landed upstream since `1ece6e6db`. Each is still a patch of this series because the base predates
its merge; the next re-seat onto a base that contains the commit retires it.

| unit | what upstream now carries | landing commit on main | PR | instruction |
|---|---|---|---|---|
| 0007 | the draft head's rows 4-bit by default (`TF_FLASHNEXT_DRAFT_HEAD` read through `platform/environment.zig`, `affine4` the default) | `230837886` (2026-11-21) | #3477 | Retire 0007 at the next re-seat onto a base that contains `230837886`, after checking the base's own default is `affine4`. Do not re-add it. |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | `174cfff34` (2026-11-20) | #3727 | Retire 0011 at the next re-seat onto a base that contains `174cfff34`. Do not re-add it. |
| 0017 and its contract 0019 | lane calls split over K on a cluster run on the fused form, and the kernel contract that gates it | `308d5e1fd` (2026-11-21) | #3475 | Retire both at the next re-seat onto a base that contains `308d5e1fd`. Do not re-add them. |
| 0004, the gather-early half only | one pooled n-gram gather for every row a shared pass needs | `69e4d0f04` (2026-11-21) | #4009 | Retire the gather-early half at the next re-seat onto a base that contains `69e4d0f04`, keeping the rest of 0004: its row cache and draft-ahead are in no upstream commit, so 0004 is NOT absorbed as a whole. Do not re-add the half. |
