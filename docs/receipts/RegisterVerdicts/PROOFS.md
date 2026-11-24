# The register's evidence check: clean run and its two failure proofs

`scripts/qwen38/zig/target/env/check-register-evidence.py` is the gate behind "one verdict a row, each with a
citation that resolves". The coverage checker (`check-env-coverage.py`) matches the evidence field as text and
never opens the file, so a verdict can pass it while citing a path that does not exist; this check opens all of
them and, where a verdict cites `path:line`, reads that line and requires it to contain the setting or a read
call. Fixtures below are register copies with one line changed.

## Clean run, on the register as committed

```
$ python scripts/qwen38/zig/target/env/check-register-evidence.py
register: 114 dev rows, 153 dev verdicts, 114 rows covered, 0 rows without, 118 prod verdicts, 1 image-baked
register: kinds absent 4, debt 31, inert 57, launcher 13, measured 8, raw 3, retired 37
register: 193 evidence path(s) opened, 108 cited line(s) read, 45 verdict(s) cite a file without a line number (the older style)
register-check: 0 problem(s)
rc=0
```

## Proof 1: a verdict with no citation fails the coverage gate

```
$ python scripts/qwen38/zig/target/env/check-env-coverage.py --table work/DevTree/zig/src/platform/environment.zig \
    --dev scripts/qwen38/zig/target/env/dev.env --scopes flashnext,cuda,common --passes '^(TENSORFOLD|TF_)' \
    --register docs/receipts/RegisterVerdicts/fixture-no-citation.env
coverage: 99 settings in scope, set 99, missing 0, absent 2, annotations 99, worklist markers 0, passage-lost 0
fixture-no-citation.env: TF_FLASHNEXT_PROMPT_BF16 (debt) cites no evidence path
rc=1
```

## Proof 2: a citation to a path that does not exist passes the coverage gate and fails this one

```
$ python scripts/qwen38/zig/target/env/check-env-coverage.py ... --register docs/receipts/RegisterVerdicts/fixture-missing-path.env
coverage: 99 settings in scope, set 99, missing 0, absent 2, annotations 99, worklist markers 0, passage-lost 0
rc=0

$ python scripts/qwen38/zig/target/env/check-register-evidence.py --register docs/receipts/RegisterVerdicts/fixture-missing-path.env
register-check: 1 problem(s)
MISSING-PATH TF_FLASHNEXT_PROMPT_BF16 (line 136): work/no-such-tree/zig/src/environment_moved.zig
rc=1
```

The pair is why both checks exist: the first proves the coverage gate can fail on a verdict, the second proves
this check is load-bearing because the coverage gate never opens the evidence file.

## The four env gates on the same tree

```
coverage: 99 settings in scope, set 99, missing 0, absent 2, annotations 99, worklist markers 0, passage-lost 0   rc=0
dev-env: 0 setting(s) without a citation                                                                        rc=0
launcher-contract: 0 problem(s)                                                                                 rc=0
check-python: CLEAN                                                                                             rc=0
```

The `annotations 6 -> 99` change is this work: the field counts in-scope rows carrying a verdict, 93 of the 99
gained one, and the other 14 added verdicts name carried-not-a-row settings.
