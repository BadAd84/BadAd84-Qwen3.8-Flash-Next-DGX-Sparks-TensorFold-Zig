# Upstream PR (not posted): patches/0014: copy re-sync after an edit and a wider copy ramp

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w2-fable (`~/work/lanes/w2-fable/README.md`, holds hold4-hold7), merged image `zmerge4` (`merge/mverify6.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0014: copy re-sync after an edit and a wider copy ramp (one-word rewrites +31%, four-word rewrites 2x; replies byte-identical)

**Body:**

## Description and Motivation

When a copy window misses (the reply edits the text it is copying), the copy proposer goes quiet until a
new suffix of `min_match` tokens matches again, and the lone stream's window falls back to 15 rows; an edit every few
lines never climbs the 15 -> 31 -> 63 ramp of `0013`.

`patches/0014-flash-next-copy-resync.patch`, all of it drafting policy:

- `TF_FLASHNEXT_COPY_RESYNC=1` (`core/lanes/proposer.zig`): after a copy that had landed 2+ rows misses, the
  proposer resumes the source right past the edit, without waiting for a new match. At the miss itself the target's
  token tells a deletion (it is the source's next token) from a substitution (resume past the replaced token); later
  it matches the last two tokens written within 24 source tokens of the miss, or the last one within 4 (an insertion,
  the end of a longer replacement). At most 2 guesses a miss, never counted toward the proposer's silence.
- `TF_FLASHNEXT_COPY_RESYNC_PROMPT_ONLY` (on unless `0`): only copies whose source lies in the prompt resync. A reply
  that repeats its own earlier lines (code's tests mirroring a call, lists) leaves the source at every miss, and a
  resync there only costs rounds.
- `TF_FLASHNEXT_COPY_RAMP=jump`: after a copy round that kept every row, the next window is the widest at once (rows
  between the head's window and 64 cost about the same per kept token).
- `TF_FLASHNEXT_COPY_MISS=keep`: after a round that missed, the window keeps its width instead of falling to 15.
- The boot log says `copy policy: after a missed copy round keep, after a clean one jump, resync on (copies out of the
  prompt) ...`. Unset, the engine keeps its own policy (`0` / `double` / `first`).

Why the replies do not change: these only choose which tokens are proposed as copies and how many; every copied
token is verified like any draft.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). One client, lane image with `0013`, one hold (hold7: a warm-up boot first):

| 1 client, tok/s | 64-row windows | + this policy |
| --- | ---: | ---: |
| one-word rewrite | 408 | 534 |
| four-word rewrite | 151 | 305 |
| one-line code edit | 503 | 546 |
| verbatim copy | 756 | 752 |
| a rename to a longer name | 406 | 392 |

Normal decode is untouched: with the prompt-only gate the quicksort prompt took 84 rounds, 562 drafts, 427 accepted,
the control's exact counts, and the prose rounds were identical (without the gate the same prompt took 86 rounds: -3%
on it). The rename case loses 3%: `MISS=keep` makes its two wrong guesses 63 rows wide (`TF_FLASHNEXT_COPY_MISS=first`
keeps it at ~406). Merged build (with `0012`, `0013`, `0016`-`0018`, and `0020`'s drafting change in the same step):
one-word rewrite 432-434 -> 578-585 tok/s, copy 811-812 -> 814-816, cold prefill unchanged.

Arms dropped (measured): the copy entry gate at 4 matching tokens (code -5 to -9%), the proposer's silence at 4 rounds
(no effect), `MISS=half` (below `keep`), arming only after 4 landed rows or 1 guess (no code gain, four-word rewrites
-9 to -10%); the patch here has none of them, nor their switches.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. Every copy/rewrite/rename/edit reply had one sha across every arm (holds hold4-hold7).
- Host tests (`core/lanes/proposer.zig`): a resync proposes the source past a one-token edit, realigns on the tokens
  written and gives up after its tries; it is armed only by a copy that was landing; and only by a copy out of the
  prompt.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (a few fields a proposer).

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR] merged first (logically it builds on #[0013's PR]'s windows). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
