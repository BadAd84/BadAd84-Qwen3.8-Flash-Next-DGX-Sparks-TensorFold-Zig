# The old engine fork `ots/tensorfold-levers124`, kept whole

`levers124.bundle` is a git bundle of everything that fork (and its one working clone) held that upstream
`ashhart/TensorFold` does not: 59 refs, 227 commits, 1,983,230 bytes, sha256
`ff2234e47d486eb9700e50dceb818d1097f6b2130d2b2e7fd521723f51c1ef36`. `REFS.txt` lists each ref and its sha. Taken
2026-11-12 so that the fork can be retired without losing anything.

What is in it:

| refs | what |
|---|---|
| `refs/remotes/origin/main` = `27b6700cb` ("c68-shared-cost-levels") | **the production engine source**: the zmerge8 stack, 23 commits on upstream `db281878d`. The image spark6 serves (`zmerge8-kfix-e5139fcd8c6101c7`) is this tree plus two boot fixes. This was its only git home |
| `refs/remotes/origin/1.2.6` | upstream v1.2.6 plus `speed_target.md`, which is byte-identical to `docs/SPEED-TARGET-1.2.6.md` here |
| 36 `refs/tags/archive/*` | the development branches the lever patches were cut from (1.2.4 ports, the 1.2.6 levers, the resync and row work) |
| 21 `refs/heads/*` | the working clone's local branches; `fix126` and `stack126` carried 12 commits that were never pushed |

Two refs were left out because they point at upstream's own commits: `refs/heads/1.2.4` (`267c5af6a`) and
`refs/tags/archive/base-0013` (`1bb0ea270`).

## Restore

In any clone that has upstream TensorFold's history:

    git fetch /path/to/levers124.bundle 'refs/remotes/origin/main:refs/heads/production-zmerge8'
    git fetch /path/to/levers124.bundle 'refs/tags/archive/*:refs/tags/archive/*'

`python verify_bundle.py levers124.bundle <a TensorFold clone> REFS.txt` restores every ref into a throwaway clone
and compares the shas (59 refs, 0 mismatches, connectivity ok on 2026-11-12).
`python deep_check.py levers124.bundle <a full TensorFold clone>` walks every object of the restored refs, blobs
included (59 refs, 90,134 objects, 0 missing on 2026-11-12; the fork's working clone was a blobless partial clone,
so this is the check that the bundle did not inherit a hole).

The production engine source is also a branch of this repository now: `production` (the tree the serving image was
built from, one boot-fix commit past `27b6700cb`).
