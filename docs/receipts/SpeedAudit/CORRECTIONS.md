# Corrections to REPORT-kimi.md, from the verification pass and the series window

Three numbers in the first audit are wrong. Each correction names the file that settles it. Read this beside
`REPORT-kimi.md`; the audit's conclusions stand where this file does not touch them.

## 1. The one-stream chat row of the engine/checkpoint split

`REPORT-kimi.md` section C.2 gives `P/F 1.1661`, `P/I 1.1680`, `I/F 0.9984`, engine share `101.1%` and checkpoint
share `-1.1%` for one stream, chat. A negative checkpoint share is impossible in that decomposition: the three
ratios multiply to one only if each share is positive. The row was built from single cells.

Recomputed from `docs/PROD-VS-ZIG-2026-11-18.md`'s own table (production `P` 69.4, ours on INT4 `I` 65.0, ours on
FP4 `F` 63.4, all at one stream, chat):

    P/F = 1.0946    P/I = 1.0677    I/F = 1.0252
    engine share     = ln(1.0677) / ln(1.0946) = 72.4%
    checkpoint share = ln(1.0252) / ln(1.0946) = 27.6%

`work/SpeedAudit/REPORT-verify.md` reads the source's own repeats and gets about 80/20 for the same cell. The two
differ because they use different cell picks, not because either method is wrong; the robust statement is that the
checkpoint is a POSITIVE share of the one-stream gap, roughly a quarter to a third, and the engine is the rest.
Nothing in this campaign may quote `2.10x` as an engine gap: that ratio compares production on INT4 at 262,144 with
fp8 KV and vision on against main on FP4 at 32,768 with bf16 KV and vision off.

## 2. The six latency cells are faster, not level

`REPORT-kimi.md` and the box's own `TABLES.md` read `level` for every latency cell, because the analyzer negated both
sides and reused the throughput test. Measured after the fix, on the same fetched arms
(`work/CacheState/RESULT.md`, `tables-before.out` against `tables-after.out`): faster on all six, by 3.9 to 6.4
percent. The analyzer now reports them as faster, and its self-test exits 0 with planted faster, slower and level
cases.

## 3. The decode cells carry 126 reply hashes an arm, and all four arms agree

The box's table reported `0` hashes and `differing 10` cells. The harness wrote them all along under
`cells[].reps[].evidence[]`, and the analyzer read `cell["evidence"]`. After the fix: 126 hashes an arm across the
ten decode cells, `identical 10 cells, differing 0`, and the six golden prompts keep six hashes each where the
merged file had `[]`. So exactness IS established for the series window's decode and golden cells, and the record
must say so rather than "not captured".

The one thing the hashes do NOT settle is the longer prompt: the 8,606-token reply still differs between cold and
cached with drafts on, and between drafted and `"draft": false` in one cache state. That is `work/RowInv/`'s
question, and it is a blocker for shipping the series, not a measurement defect.
