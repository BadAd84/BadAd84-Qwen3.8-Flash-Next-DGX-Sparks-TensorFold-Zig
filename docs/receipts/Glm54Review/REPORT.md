`[Done]` Read-only review complete. Every finding below was checked against the named file in this repo.

# Independent review of this session's work (read-only)

**Verdict.** The engineering under the work is better than the sentences describing it. The shared-draft stop, the
tier's write accounting and dedup patch, the int4 device receipt and the draft-head mechanism hold against their
artefacts. What I would not stand behind is the state the repo is left in: `dev.env` has never been booted as written
and differs from the environment of every receipt it cites; the tier is not in any image the dev arm serves; the knob
screen is armed with a dead arm, a stale base and a rule that can kill on one boot; and the committed evidence base is
gitignored scratch. Detail and the order of repair are in sections 3 and 4.

## 1. Claims against their artefacts

| # | claim | verdict | what the record shows |
|---|---|---|---|
| 1a | tier appends resume in 1.04 to 1.23 s against 44.2 to 44.7 s cold | supported, narrow | two turns, one 100k conversation: 1.042 and 1.226 s against 44.206 and 44.305 s (`work/KvTierShip/RESULT.md` 102-135). Other cold twins read 46.7 to 47.4 s; the top of the quoted range is W4's |
| 1b | equal-depth exactness at four depths | supported as "320 greedy ids equal", not as written | strict RAM pairs exist for two depths only (R1, R2); the other two have no RAM twin (`work/KvTierW5/tables.md` 57-65, "UNRUN"). "Byte-equivalent" (`RESULT.md` 120, 321) is not shown, see F3 |
| 1c | decode level at every admitted stream count | supported by the rule; the rule is weak there | ON slower in 9 of 10 cells, by 1.4 to 2.9 percent at 1 to 4 streams; verdict from a disjoint-range rule. Warm waves against warm waves agree within 0.4 percent, so the conclusion holds; the rule could not have detected a 2 percent cost |
| 1d | write cost halved, 228 to 115 MiB, 60 GiB holds 508 turns | supported for short replies only | mean of turns 6, 8, 9, 10; turn 7 wrote 231.2 MiB on both arms (`work/KvTierDedup/RESULT.md` 25-28, 161-172). 508 is the short-reply bound; a turn after a reply of 256 tokens or more writes double |
| 1e | 8 x 262,144, 6 GiB ask, 3.1 granted; owner chose; dev.env records it | comment only | `dev.env` 37-45 is a comment; the sole export is `TF_FLASHNEXT_KV_PAGES`. Lines 42-44 say the shipped r5int4 image has no tier patch and refuses `--learn-conversations` with `--prompt-cache-disk`. The tier exists only on one-off images |
| 2a | cause is upstream's `shared_stop = 0.6` at `cuda_lanes_draft.zig:26,30` | verified | the served copy is byte-identical to upstream `556094fc`'s file; lines 26, 30, 40, 47 match `work/UpShared/issue.md` |
| 2b | +7.3 to +11.2 percent at 2 to 8 streams, level at 1, 54 percent of the gap | supported at 4 streams; thin elsewhere | two boots an arm at 1 and 4 streams, separated; one boot an arm at 2, 6, 8 ("indicative", `work/ProseDraft/RESULT.md` 252-265). 54 percent is the four-stream prose gap only |
| 2c | a find | a re-find | the same knob and rule are measured and written up on 2026-11-14: `docs/INT4-PORT.md` 280-293 and `patches/1.2.7/README.md` 194-216 |
| 3a | register keyed to the engine table; 95 rows, not 78 | verified | served-tree manifest equals the image label (`work/EnvServed/RESULT.md` 11-17); my plain grep of the served table: 232 rows, 95 in scope, equal to the gate's count |
| 3b | `native` and `unset` as the only absence forms | sound | `absence-probe.txt` shows a valueless export passes an inherited value through; the launcher loop was read from the box |
| 3c | no setting unset | true of the file, not of the serve | 26 of the 95 never reach the container (advisory only, `coverage-after.txt`); 18 rows are other families by `docs/KNOB-COVERAGE.md`'s own class; four INT4 rows are absent, see F1 |
| 4 | docs and rules reduced to current state | partly | twelve deletions are defensible and swept for links; the front page and two docs are stale, see F8 |
| 5 | 78 settings classified; screen designed | wrong tree; not run | `docs/KNOB-COVERAGE.md` 3-8 is against `work/Int4Step5/tree`, which `work/EnvServed/RESULT.md` 19-21 says is no served image's tree |
| 6a | int4 device summary and gate 3 | verified | `work/Int4Device/RESULT.md` 51, 73-75, 85-86: rc 0, 8 kernels, three prompt forms bit-equal (7, 7, 8 shapes), both controls red |
| 6b | step 4 "DONE pending their review" | overstated | full registry run stopped (rc 137); limits audit rc 1 with 550 problems; no base run; see F6 |
| 6c | quality equal to FP4 over 1,664 items | glossed | HumanEval 143/164 against 135/164 (`work/EnvBoot/RESULT.md` 171-172); the 2026-11-19 INT4 arm read 133/164 |
| 7a | draft-head mechanism and line references | verified | all seven references match the patch hunks' old numbering; the defect is ours (patch 0014): upstream at `1ece6e6db` and at `556094fc` has no `recode` |
| 7b | device window: 28 comparisons equal, 184 drafts in 48 rounds | no artefact in the repo | `work/DraftHeadBf16/RESULT.md` 49-60 still says in flight; no receipt fetched; `RECORD.md` line 22 is committed as `<<GATES>>` |

## 2. Method

**The C-A-C screen (`work/KnobScreen/RULE.md`).** A second control is right in principle and the midpoint absorbs
monotone drift. Four things make the rule as written unsafe to run:

- KILL fires on any one of six judged cells from one candidate boot, margin `max(|c1-c2|/mid, 1 percent)`. PROMOTE
  needs two cells; KILL needs one. That is the wrong asymmetry for a single-boot design.
- The repo's own rule says "never a single run: decode varies up to ~25 percent run to run" (`AGENTS.md` 62-64), and
  the session's own tier window recorded cold first waves of 8 to 10 percent on two of ten fresh-boot cells
  (`work/KvTierShip/RESULT.md` 85-89). `d1-prose` is the first cell measured on every screen boot. UNSTABLE at 25
  percent cannot catch that.
- Two controls give a range, not a spread. Twelve candidates in one window would give twelve control pairs; the rule
  uses one.
- The base is not the committed file. `driver.sh` 25, 180, 183 read `$REF/dev.env`, which is `work/KnobScreen/ref/dev.env`
  (85 statements, dated before the register was corrected) and still holds `export TF_FLASHNEXT_KV_PAGE_TEST=0`
  (line 213), the line `cuda_pages.zig:69-71` refuses. `dev.env.new` sits beside it and nothing reads it.

Arm 4 cannot score at all. `TF_QMMF_HALF_BELOW` fails the launcher's filter, so the container lacks it, `check_env.py`
answers ABSENT, and `driver.sh` 196-197 refuses without retry. The passage gate passed it because it sits below the
defaults marker, where loss is an advisory. `check_env.py` also predates the `unset` form (it reads only `export`
lines) and does not fail on EXTRA names.

**The env register's model.** Right on mechanics. Weak on denominator: it counts table rows in three scopes, not
settings this serve executes. And the "explicit defaults" section is not the no-op it claims (F1).

**The served-tree correction.** Sound, and reproducible. But it selected the FP4 image while the session's speed
promotions ran on the INT4 image, whose table has four more rows.

**Deleting the historical docs.** Defensible: all twelve are in git, the transfer table is specific, and the link
sweep was done. Two defects: the replacements point into gitignored `work/`, and the same rule was not applied to
the files that stayed.

**Float64 fidelity.** Not met. `AGENTS.md` 221-222 requires an independent FP64 reference per affected projection
class, prompt and decode separately, for a changed reduction order. The step table says "the float64 fidelity
reference unrun" (`docs/INT4-PORT.md` 20). Gate 3 shows bit-equality to the replaced kernel on three prompt forms
only; no decode-path line is in the record.

## 3. What is wrong or risky

**F1 (HIGH). `dev.env` has never been booted as written, and it changes what every receipt ran with.**
- The container env of the prose boots and the tier boots reads `DRAFT_AHEAD=1 GATHER_EARLY=1 GATHER_READ=pread
  HEAD_PIECE=1536 KEEP_LATE=1 PREFILL_TAIL=512 PROMPT_GEMM2=1 WARM_AHEAD=1` (`work/ProseDraft/out.fetched/out/B0a/env.txt`,
  `work/KvTierDedup/ev/out/new/seed/env.txt`). The committed defaults section states `0 0 0 256 unset 0 0 0`
  (`dev.env` 204, 214, 236, 244, 260, 264, 266, 268), and contradicts `prod.env` 44 on `PREFILL_TAIL`.
- Three of those switches the r5 README lists as patch 0004's own levers, "all on" (`patches/main-1ece6e6db-r5/README.md` 57).
  The recipe supplies them through `${NAME:-...}`, so a dev.env sourced first turns them off. `AGENTS.md` 287-291
  says exactly this, and says an arm that means "lever off" passes the explicit `=0`: the defaults section is that arm.
- `work/EnvServed/RESULT.md` 78-80 admits "None of the ten is measured here" and calls it the one behavioural
  difference. It is eight unmeasured changes in the file that replaces `prod.env`.
- The measured block is an assembly: `SHARED_DRAFTS=0` was measured without `CHUNK=4096`, `CHUNK_SOLO=16384`,
  `READOUT_FUSED=1` and `WINDOW_CHECK=1` (all absent from B0a's container env; the plan line reads 3072 rows a pass).
  `AGENTS.md` 70-74 requires a speed number from the artifact that ships.
- If INT4 is the direction, the register misses four rows and the recipe's `HEAD_ROW_TILES=2`, `INT4_PROMPT_GATE_UP=1`.

**F2 (HIGH). The tier is not delivered, and its chosen shape gives up the case it exists for.**
- Not in the dev image (claim 1e). `dev.env` 39-40 lists `--prompt-cache-disk /cache/kv` without `--learn-conversations`;
  `work/KvTierShip/SHIPPING.md` 18 says `/cache/kvtier` with it; the window used `/cache/kvs/tier`. No booted line matches the comment.
- Shape (a) grants 3,166 MiB; a 261k state is 4.70 GiB, so it is never kept and pays 127.854 s cold
  (`work/KvTierShip/SHAPES.md` 84). Conversations past about 165k tokens get nothing from the tier.
- `SHAPES.md` 27-30 and `SHIPPING.md` 65-68 say which cap binds "is not established", then conclude "raising the ask
  buys nothing". One boot at a larger ask, or two functions read with the measured inputs, settles it.
- Eight streams, one conversation. After turn 6 the cache holds 2,226 of 3,166 MiB with "0 MiB spare"
  (`work/KvTierShip/ev2.tgz: tier/t6/imprint.txt`). Whether a second 100k conversation's state is written or skipped when
  the first fills the cache is not measured, and it decides if the tier works for more than one agent.
- Turn 7's one-state write is misattributed. `RESULT.md` 110-112 credits "the dedup's boundary rule". The log reads
  resumed at 105,264, `kept 1`, and one write at 105,624; the dedup lane's same shape (turn 7 after a 320-token reply)
  kept two states on both arms because the rewind sat 331 tokens above the resume. At 3,166 MiB the budget refused the rewind.

**F3 (MEDIUM-HIGH). The exactness oracle cannot see the cached content.** Every cell in `work/KvTierW5/tables.md` 9-21
shares sha16 `277412fd297b56aa`, including the cold twin of the prompt whose 1,200-word passage was replaced
(prompt 105,142 against 105,279). The reply is a count that does not depend on the passage. So "ids equal" shows the
instruction survived, not that the stored rows are right. `work/KvTierW4/RESULT.md` 295-299 already limits the claim
("does not support byte equality for arbitrary long answers across arbitrary depths"). A logprob comparison of the
first tokens, or questions about the passages, would be a real test. `TF_IMPRINT_VERIFY` remains unused.

**F4 (MEDIUM-HIGH). The upstream issue is not ready, and it is weaker than it reads.**
- "the prompt cache on" is false: the speed arms ran with no prompt cache (`work/ProseDraft/out3.fetched/out3/B0x/plan.txt`,
  `cache-state.txt: no-cache`; `RESULT.md` 311 says so).
- No checkpoint and no `CONFIDENCE` named. The repo's own FP4 table at the default -0.4 reads +0.7 to +3.4 percent prose
  with code inside noise (`patches/1.2.7/README.md` 204-208). The 2026-11-14 INT4 table reads +10.0, +7.6, +4.4, +0.9
  percent at 2, 4, 6, 8 streams (`docs/INT4-PORT.md` 290-293). So 7 to 11 percent is one checkpoint at one stop value,
  from single boots at three widths, and the eight-stream prose figure differs eightfold between the two records.
- Measured on our patched engine, not on upstream main; the draft does not say so.
- "added 2026-11-10" is contradicted by the v1.2.4 tag, which carries the constant (`work/up124`, line 27). "Cost 7 to
  11 percent for two days" (`AGENTS.md` 267-268) has no support: it was measured at about 1 to 3 percent on FP4 nine
  days before promotion. The process failure is real: a measured lever sat in two documents and never reached `dev.env`.

**F5 (MEDIUM-HIGH). The draft-head fix is committed ahead of its evidence.** Mechanism right; host test right; the
scoping fix is pinned only on the device. `RECORD.md` is committed with `<<GATES>>`, its Checks section is empty, the
remaining Paperclip gates and both mutants are unreported, and the "28" is 16 required cross comparisons plus 12
within-arm ones (`work/DraftHeadBf16/box/compare.py`), on three short prompts and one of about 1,200 tokens, 64 greedy
tokens each. Its patch numbers 0021 and 0022 collide with the tier package's, and the CHANGELOG line carries `(#9999)`.

**F6 (MEDIUM). The int4 port's open edges are larger than the step table says.**
- 550 stale limit records: "pre-existing" is a negative claim with no control. The same audit on base `7bd7081e0`
  was not run. One window settles it.
- The full registry run is the receipt the maintainer asked for. It did not reach the trailing suites, the in-process
  gate 5 section, or the kernels after the moss family. `docs/INT4-PORT.md` 345 still says "Outstanding: the device
  summary" while line 19 says DONE.
- The box hard-reset during the first run. The rerun was stopped inside the same moss `shapes` gate, so "It did not
  recur" is not shown. No pstore or panic record is cited. Do not re-queue that run on the shared box before this is closed.
- The quality scorer cited by sha `87cb9c00` is the uncommitted working copy; HEAD's blob hashes `9b583cce`.
- "Equal to FP4" hides an 8-item HumanEval deficit on the INT4 arm, in the same direction on two days.

**F7 (MEDIUM). Evidence durability.** `.gitignore` 13 ignores `work/`; zero files under it are tracked. Every citation
in `dev.env` and in `docs/` is a `work/` path, and the deleted docs' replacements are too (for example
`docs/PROD-VS-ZIG-2026-11-18.md` became `work/DevVsProd/RESULT.md`). The scratch rule says the job that made it
removes it. A fresh clone cannot support any number in the env of record. `prod.env` is a hand copy of the container's
env that drifted from 52 to 54 settings between copies and has no check against the live container.

**F8 (MEDIUM). Current-state-only was not finished.**
- `README.md` 18-20 and 29 say the quality defect is open and no r5 run exists; `docs/INT4-PORT.md` 306-325 says it does
  not reproduce on r5, measured on both arms. The docs list in `README.md` omits `KNOB-SCREEN.md` (ten files, nine bullets).
- `docs/KNOB-COVERAGE.md` 3-8 still prints "78 ... the complete set" against the non-served tree.
- `docs/KNOB-SCREEN.md` 86-92 says the 17 rows are not in `dev.env` and "no arm sets them"; false since `c70f8d13`.
- `AGENTS.md` 280-286 tells every agent to type-check on the laptop, against the owner's later no-laptop-compile rule.
- `dev.env` 108 cites `cli.zig:250` as a reader of `TENSORFOLD_PARALLEL`; that line is a CLI struct field, and the served
  tree has no occurrence of the name. `docs/ENV-REGISTER.md` 201 says so; `docs/KNOB-COVERAGE.md` 50 says the opposite.
- Uncommitted: the scorer, a whole-file change to `check-env-coverage.py`, the untracked package
  `patches/main-1ece6e6db-r2-int4/`, about twenty untracked scripts, `relabel.sh` at the root, and three empty root
  directories named `=== A merge-tree ... ===`, `and`, `echo`.

**Smaller.** The tier's LEVEL verdict at 1 to 4 streams is under-powered (warm waves agree within 0.4 percent; say
that, not the rule). "508 turns" and "115 MiB a turn" need the 256-token caveat wherever they appear. `dev.env` 38 says
"replies byte-equal" for 320 and 32 ids. `work/KvTierW5/RESULT.md` 136-144 leaves W4's pair open; W4 closed it as a
misreading. `docs/AFFINE3-TILE-MISPICK-2026-11-06.md` is a dated record on another family and survived the cut.

## 4. Suggestions, ranked

1. **Do not promote `dev.env`.** Boot it once as written and measure that boot. Until then restore the eight values to
   what the receipts ran, or measure the flip as its own arm. State which image it is for; if INT4, cover its four rows.
2. **Fix the screen before it takes the lock.** Point `REF` at the committed file; drop or re-plan arm 4; KILL only on a
   treatment cell or require a second candidate boot; discard a warm-up; pool the spread over all control pairs; teach
   `check_env.py` the `unset` form and fail on EXTRA.
3. **Say what the tier is.** A validated package on a one-off image, not a shipped feature. Close the cap question;
   measure two interleaved 100k conversations at eight streams; strengthen the oracle (F3); correct turn 7's attribution;
   make the `dev.env` comment match a line that booted.
4. **Redraft the issue.** Drop "prompt cache on"; name the checkpoint, `CONFIDENCE` and the engine; report the FP4 numbers;
   add boots at 2, 6 and 8. Consider proposing the gate derive from `CONFIDENCE` rather than a fixed default flip.
5. **Finish the draft-head package.** Fetch the receipt, fill `<<GATES>>`, run M1 and M2, renumber 0023 and 0024.
6. **Int4.** Base run of the limits audit; the reset's cause from pstore before any re-queue; fix the step table and the
   PR section; commit the scorer; report HumanEval plainly.
7. **Docs.** The five stale statements in F8, and the two dates in F4.
8. **Track the receipts.** Copy every cited `work/` file into a tracked `docs/receipts/`, as upstream does, or the next
   scratch sweep deletes the evidence. Add a `prod.env` against live container check to each window's restore step.

**What I would not do.** Post the issue as drafted. Let the screen run as armed. Flip an upstream default on one
checkpoint's numbers. Re-queue the full kernel-contract run on the shared box. Spend GPU re-measuring the dedup's write
shape or the shared stop at four streams: both are well measured. Prune more rules mid-campaign.

## 5. Verdict

I would stand behind about half by effort, most of it by value: the shared-stop diagnosis and its four-stream cells, the
tier's mechanism and write accounting with the dedup patch and its both-ways host test, the env presence-form analysis
and the served-tree identification, the int4 suite and gate 3, and the draft-head mechanism. Each needs the wording
narrowed where section 1 says so.

I would not sign the session off as it stands. First, in order: F1 (one measured boot of the committed `dev.env`), F2's
first bullet (the tier stated as undelivered), the screen's base and arm 4 before it runs, and the draft-head receipt
into the repo. Then the issue redraft, the int4 base run and reset cause, and F8.
