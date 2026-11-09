Title: lanes: copy re-sync past an edit, and the lone copy ramp in shared rounds

## What this changes
Flash Next's proposer loses its source the moment a drafted window misses.
`SuffixLookup` re-finds the stream's history by 3-gram and copies the longest suffix match, so one changed word
inside a copy span denies the next match for quite some rounds and a reply that repeats and edits a file keeps
falling back to 1 token a round across each edit.

This adds an optional copy resync that keeps the source position past a rejected draft and proposes from there
without waiting for a fresh match, plus a copy ramp policy and a shared round rule. Every part is off by default, so
a default boot is exactly like always was.
- Issue: n/a, this is a lane proposer feature behind off-by-default settings (not a new family, backend or
   arithmetic change) and it changes only which tokens get proposed as drafts, never the math. A draft is still
   accepted only when it equals the plain token.
- Stacked on: the copy-window-width PR (this change is written against the 48-row default; the receipt here is measured on that base).
- Overlap:
   `atc overlap --json` on this head: 21 changed files, 53 open PRs share at least one of them and
   one hard merge conflict - #1394 (Llama2, DSpark drafting), which touches the same `core/lanes` files on 2
   paths and needs sequencing with this change. No other code conflicts. The board snapshot is partial
   (`pullFilesLimit`).
- Not run: Metal, HIP and XPU host tests (this box is CUDA only) and any GPU kernel contract (no kernel changes).

## Checks on this head:

- Head commit: `cb32b158b` (the 48-row receipt on the stacked branch: this change cherry-picked onto the 48-row window head; the receipt adds `docs/receipts/flashnext-copy-resync/`). Gitea branch `resync-on-48`.
- `tools/pr_check.py --base origin/main`: 0 errors, 0 warnings; lean 116 vs 116, 0 new (each tree with its own copy of the checker).
- Tests:
  `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU, no network. Base and head fail exactly the same three environment tests: one listener test that needs a network, two `drama_voice_tool` cleanup tests that expect `error.AccessDenied` while the container runs as root. The four added tests pass.
- CI: not run here (local gates above are the local equivalents).
- Not run and why:
   Metal, HIP and XPU host tests (this box is CUDA only) and any GPU kernel contract (no
   kernel changes).

## Receipt

A full receipt is in `docs/receipts/flashnext-copy-resync/` (README, the two bench tools' output on both arms, the rewrite workloads, SHA256SUMS).

- - Boxes it reaches: one NVIDIA GB10 (DGX Spark class), CUDA, the NVFP4 checkpoint. Levels measured 1, 2, 4 and 6; GPU temp 58-67 C across the matrix.

- The switches, all unset by default, strict values that refuse an unknown name at start:

| setting | values | default |
|---|---|---|
| setting | values | default |
|---|---|---|
| `TENSORFOLD_COPY_RESYNC` | 0, 1 | off |
| `TENSORFOLD_COPY_RESYNC_PROMPT_ONLY` | 0, 1 | prompt copies only |
| `TENSORFOLD_COPY_SHARED` | 0, 1 | off |
| `TENSORFOLD_COPY_MISS` | first, keep | first |
| `TENSORFOLD_COPY_RAMP` | double, jump | double |

Environment: both arms built from the same tip (the 48-row window base). `resync48-up` is that base's stock; `resync48-cw` is this change. Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuses `--kv-cache fp8`), 131,072-token windows, `--parallel 6`. Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`). Device scratch 4.29 GiB at 1 stream / 4.16 at 2-6 on both arms; the boot self-check reads "widths 1-48 row-equal, serving 48-row copy windows" on every boot.
Levels are 1, 2, 4 and 6. The stock arm cannot serve 8 streams at bf16 KV on GB10: eight 131,072-token windows need 32.86 GiB of cache against the 31.41 GiB the budget leaves, so 8 does not admit.
Paths this change reaches:
The decode-time copy proposer in `core/lanes`. Ran on CUDA/GB10; did not run Metal, HIP or XPU.
Exactness, same checkpoint and settings:
- Golden 6/6 identical on all 12 boots: every `resync48-cw` reply equals stock `resync48-up`'s own reply on every cell.
- `tools/bench_concurrent.py --alone --serial`: 0 failed and 0 unmeasured requests at every level on both arms; the reply-level equality is the golden comparison and the workload hashes below.
- Every workload sha is equal between the two arms (copy, rewrite, edit2.0/1, editprose.0/1 - 1 distinct sha per (streams, workload)).
- Main against this branch, same machine and checkpoint, the lever's own workloads (medians, `resync48-up` / `resync48-cw` tok/s, the 48-row base):
| workload | resync48-up / resync48-cw | change |
|---|---|---|
| one-word rewrite (1 stream) | 254.3 / 377.7 | +48.6% |
| two concurrent edits, 1st / 2nd | 135.6 / 195.6, 136.6 / 210.2 | +44.2% / +53.9% |
| edit beside a prose reply, edit / prose | 145.9 / 297.4, 50.1 / 50.1 | +103.8% / +7% (prose overall: 46.9 / 50.1) |
| verbatim copy (1 stream) | 467.5 / 468.5 | +0.2% |
The copy path is untouched, as designed. Everything else roughly doubles, since the source
now survives an edit at the 48 row window's depth (the re-sync carries the position past the rejected
draft and the lone-copy ramp covers the restart). The numbers stack on the 48 row receipt's own base
(up48 is 254.3 vs the 32 row receipt's upab4 230.5 - The wider window alone bought the edit paths ~10%)
- Decode speed before and after, `tools/bench_openai.py` one request at a time, greedy (six boots an arm, `decode_tps_median`): code 71.5-72.8 stock against 71.4-71.9, gpu-chat 46.0-46.5 against 46.0-46.2. Plain decode is unchanged within the boot spread - not a regression, and not a gain.
- Prompt speed before and after: n/a. The change is in the decode-time copy proposer and does not reach prompt processing.
- Licence: n/a, no new weights.

## Stacking
This change is written against the 48 row copy window (its own PR), the receipt here is measured on that
base and they land in this order. It also carries the shared round ramp rule, which the 48 row
window's receipt does not include.

## Checklist
- [x] The title and description match the head commit, including the receipt and the stack.
- [x] New tests fail before it, pass after and skip cleanly without their dependency. (4 faithful mutants, all killed by its named test - the prompt only arming gate, the miss arming and the shared round ramp and width).
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits. No AI attribution lines.
- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [x] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo.
- [x] No precision for speed (it just picks which tokens are proposed as drafts - it changes no sum).
- [x] Decode and Prompt processing are no slower than main at 1 stream and the widest admitted. With the copy policy on, edits are faster and plain decode is within noise.