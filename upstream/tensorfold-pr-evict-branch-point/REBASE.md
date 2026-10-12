# Rebase onto TensorFold main 0efbd447 (2026-10-12 13:10)

- Bug still present: main plus only the new tests fails both repro tests (`expected 100117, found 0`; `expected 20, found 0`).
  None of the 6 commits touching prompt_cache.zig since e7c523eb changes `victimBut`/`resumed`; new `giveBack` (b870749f, Qwen3.8-27B slot) also evicts via `victimBut`, so it gets the fix too.
- Only conflict: the test-import hunk (main added prompt_cache_learn_test / prompt_cache_give_test imports); branch_test import placed after rewind_test. All other hunks applied unchanged. Diff still 5 files, +147/-9; `git apply --check` clean on 0efbd447.
- zig build test: main 616/621 (5 skipped) -> fix 623/628 (5 skipped). Test-only: 620/628, 3 failed.
- zig_test.sh: main 155/155 and 96/96 -> fix 155/155 and 100/100. Test-only engine seam: 98 passed, 2 failed.
- Mutants 7/7 killed by exit code (radix-mark-always now reported against the full test name "a shared cut outlives the conversation that made it, and a state its conversation moved past goes first").
- lean_check: no new problems; zig fmt --check clean. Build used -j4, nice 19, CPU only.

## Values to change in the approved PR text
| final.md line | old | new |
|---|---|---|
| 26 | TensorFold `e7c523eb` | TensorFold `0efbd447` |
| 31 | main 451/451; this change 454/454 | main 616/621 (5 skipped); this change 623/628 (5 skipped) |
| 32 | main 127/127 and 104/104; this change 127/127 and 108/108 | main 155/155 and 96/96; this change 155/155 and 100/100 |
| 33 | failure strings | unchanged (`expected 100117, found 0`, `expected 20, found 0`) |
| 34 | 7 of 7 killed | unchanged |
| 9 | "a 4,096+ token prompt keeps its history" | still true for unplanned families; since 2a6c85ab a planned family keeps marks under min_prompt too (prompt_cache.zig:382). Consider "a prompt that keeps anything" wording |

No file:line in final.md (only function names `victimBut`, `pick`). For reference new locations: prompt_cache.zig victimBut :524, resumed :361, min_prompt :88/:382, giveBack :182; prompt_radix.zig superseded :240, pick :247, victim :258, min_prompt :153.
