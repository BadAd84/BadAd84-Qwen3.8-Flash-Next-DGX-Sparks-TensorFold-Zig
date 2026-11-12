# The engine fork `ots/tensorfold-fp4port`, kept whole

`fp4port.bundle` is a git bundle of everything that fork holds that upstream `ashhart/TensorFold` does not: 1 ref
(`refs/heads/fp4port` = `cf5807dda`), 59 commits on upstream `db281878d`, 1,309,949 bytes, sha256
`72a6102b9e21c5810d28e3f175ed70fe6f2b4a888edc4b5ee9857fd8c0121de8`. `REFS.txt` lists the ref and its sha. Taken
2026-11-12, so that the fork can be retired like `tensorfold-levers124` was: this repository keeps levers as patch
files and has no private engine fork.

What it is: the port of the production lever stack onto the NVFP4 checkpoint's engine line, from 2026-10-25 to
2026-11-07 (the recipe's patches 0001-0031 as commits, then our levers as 0032-0050 with their fixups). The record
of that work is `docs/FP4-PORT-AND-RETEST.md`.

## Restore

In any clone that has upstream TensorFold's history:

    git fetch /path/to/fp4port.bundle 'refs/heads/fp4port:refs/heads/fp4port'

Checked on 2026-11-12 with the two scripts of `../tensorfold-levers124/`:

- `python ../tensorfold-levers124/verify_bundle.py fp4port.bundle <a TensorFold clone> REFS.txt` restores the ref
  into a throwaway clone and compares the shas: 1 ref, 0 mismatches, connectivity ok.
- `python ../tensorfold-levers124/deep_check.py fp4port.bundle <a full TensorFold clone>` walks every object of the
  restored ref, blobs included: 11,016 objects, 0 missing.

The Gitea repository still exists on 2026-11-12; removing it is the owner's decision.
