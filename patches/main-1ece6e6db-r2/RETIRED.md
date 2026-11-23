# Levers upstream has absorbed (hunk level)

No patch of `patches/main-964174ea05` is wholly retired on `1ece6e6db`: two patches each held a second lever that no
upstream commit implements, so both were re-seated in reduced form. What was dropped, and the commit that carries the
same behaviour on main:

| from patch | hunk retired | upstream commit | PR | evidence on `1ece6e6db` |
|---|---|---|---|---|
| 0005 | `default_chunk` 1,536 -> 3,072 in `cuda_batch_state.zig`, its startup check in `cuda_startup_test.zig`, and the scratch-bound test in `cuda_batch.zig` | `e172bcc29` "perf(flashnext): a prompt pass holds 3,072 rows by default" | #3726 (merged 2026-11-19T22:50:19Z, merge `bc99bab7b`) | `cuda_batch_state.zig` reads `pub const default_chunk: usize = 3072;`; `cuda_startup_test.zig` checks `3072`; `cuda_batch.zig`'s test is "a pass's scratch at the default chunk stays under three gigabytes" with `< 3 << 30` |
| 0008 | the fused prompt read-out: `flashnext_hcn.cu` (486 added lines), `flashnext_hcn` fatbin and blob entries, `cuda_tile_kernels.zig`'s hcn tiles, `cuda_tiles.zig`'s `nativeFused`/`readoutFused`/`pickDown`, `cuda_batch_hc.zig`'s `promptFused`/`writeback`/`mlpWriteback`/`readout`, the HC2 knobs (`TF_FLASHNEXT_PROMPT_HC2`, `TF_FLASHNEXT_HC2_MIN`, `_DN`, `_UP`), their environment rows, and the `hc-fuse` test | `12233bee5` "flashnext cuda: TF_FLASHNEXT_READOUT_FUSED, a prompt pass's BF16 read-out on two fused tiles", refined by `7358f5c4f` | #3413 (merged 2026-11-20T11:10:34Z, merge `9748adc7e`) | `readout_fused.zig` reads `TF_FLASHNEXT_READOUT_FUSED`; `cuda_tiles.zig` has `fused_rows`, `nativeFused`, `pickDown`, `fusedDown`, `fusedUpMix`, `readoutFused`; `flashnext_hcn.cuh` holds the kernel bodies (293 lines) with `flashnext_hcn.cu` its 21-line unit; `tests/cuda/flashnext_readout_fused.zig` is the contract |

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
