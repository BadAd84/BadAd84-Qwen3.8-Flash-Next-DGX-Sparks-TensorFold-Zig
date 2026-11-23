## The branch head

- Head `3daeec7dff9c8ee1441b68c1f95d5d08a012d66b` (tree `d9059a30c7c8e70a50177568d1ce4d12988121f7`), three signed commits on upstream main `5780a037c998c7f801b5a6f4400c5ba23b2a444b` (tree `f1506c076c66f8bc44f382b1599a96e6cc5162aa`).
- `git log --oneline --format='%h %G? %s' -4`:

```
3daeec7df G flashnext cuda: the fused read-out contract entries use typed widths
b9e9fbb0a G flashnext cuda: the read-out's fused products under the kernel contract
08730c2dd G Flash Next on CUDA: TF_FLASHNEXT_READOUT_FUSE runs the decode read-out's reduce and mix inside its products
5780a037c N changelog: #3249 under Unreleased
```

- The third commit touches one file, `zig/tests/cuda/contract_flashnext_fuse.zig`: its six size constants are typed `usize` so the runtime selection `const width = if (down) wide else low;` has a runtime type. No kernel, record or launch changed.
- The head tree checked blob by blob from a fresh `git archive` before any build:
  `TREE verify manifest_sha 3daeec7dff9c8ee1441b68c1f95d5d08a012d66b entries 12600 mismatches 0 extra_files 0`.

## The gate the host list lacked: the nvcc builds, on a GPU-less host

Run on paperclip under `flock -w 14400 ~/work/host.lock`, `umask 022`, from a `git archive` of the head
whose tree was checked file by file against that commit's manifest (`mismatches 0 extra_files 0`). Host lines:

- `ZIG 0.17.0 sha256 7c61539af19fa408`
- `NVCC Cuda compilation tools, release 13.3, V13.3.73 Build cuda_13.3.r13.3/compiler.38244171_0`

- `zig build --summary all -Dnvcc=<toolkit>/bin/nvcc compile-cuda-tests`
  - rc 0, wall 894 s, `Build Summary: 168/168 steps succeeded`
- `zig build --summary all -Dnvcc=<toolkit>/bin/nvcc -Dtarget=aarch64-linux-gnu compile-cuda-tests`
  - rc 0, wall 833 s, `Build Summary: 168/168 steps succeeded`
- `zig build --summary all -Dnvcc=<toolkit>/bin/nvcc -Doptimize=fast --prefix <scratch>/prefix -j8 fatbins install native`
  - rc 0, wall 972 s, `Build Summary: 325/325 steps succeeded`

The runner the full build installed, which is the Dockerfile's own `install` step, carries the six new
entries and their kernel symbols, so the registrations were analysed into the binary and not merely
skipped by a host build without kernels:

```
sha256 dc31a12441d165670ab142089c2a309127e7dcde41b93e779f90e9223cb5702a size 183464944
grep match lines: 75 (the whole list is logs/runner-strings.txt)
qmmf read-out down with the act, 16-row half tile
qmmf read-out down with the act, 32-row tile
qmmf read-out down with the act, 64-row tile
qmmf read-out up with the mix, 16-row tile
qmmf read-out up with the mix, 32-row tile
qmmf read-out up with the mix, 64-row tile
tf_qmmf_hcact_bf16_16
tf_qmmf_hcact_bf16_32
tf_qmmf_hcact_bf16_64
tf_qmmf_upmix_bf16_16
tf_qmmf_upmix_bf16_32
tf_qmmf_upmix_bf16_64
```

## The cheap gates for the touched file

| gate | rc | wall s | last log lines |
|---|---|---|---|
| `fmt` | 0 | 2 | `` |
| `cuda_common_check` | 0 | 1 | `cuda common: 55 local copies, 0 violations` |
| `cuda_fragment_check` | 0 | 1 | `cuda fragments: 2 fragments, 16 includes, 0 misses` |
| `lean_base` | 1 | 3 | `zig/src/server/serve.zig:125: getenv of a name that is not a literal (read it through platform/environment.zig) / zig/src/server/tool_grammar.zig:92: direct getenv of TENSORFOLD_TOOL_GRAMMAR (read it through platform/environment.zig) / 6989 files, 168 problems` |
| `lean_head` | 1 | 2 | `zig/src/server/serve.zig:125: getenv of a name that is not a literal (read it through platform/environment.zig) / zig/src/server/tool_grammar.zig:92: direct getenv of TENSORFOLD_TOOL_GRAMMAR (read it through platform/environment.zig) / 6994 files, 168 problems` |
| `lean_new` | 0 | 0 | `lean: 168 problems, 168 on the base, 0 new` |
| `pincheck` | 0 | 0 | `files 169 failing 0` |

`lean_check.py` exits 1 whenever a tree carries any problem, so both trees' rc 1 is the pre-existing count,
not a regression: the gate is the base-versus-head difference, and `lean_new.py` reads 168 problems on each
tree, `0 new`, with the two trees' file counts differing (6989 against 6994) as a genuine pair must.

`git diff --check` needs a repository: run against the extracted tree it exits 129 with git's own usage
(the tree is a `git archive` and carries no `.git`; recorded in `logs/cheap.out` as `diff_check rc=129`). The
same command ran in the repository that holds the commit, on the same head, and exited 0 with no output:

```
cmd git diff --check 5780a037c998c7f801b5a6f4400c5ba23b2a444b..HEAD
rc 0
worktree 3daeec7dff9c8ee1441b68c1f95d5d08a012d66b
```

The pincheck ledger `zig/tests/fixtures/gradient-serving.tsv` carries no row for the contract test file (the
only file touched), so no row needed re-pinning: `files 169 failing 0` above.

## Gate gap: why the build lane's host gates passed on a branch that could not build its runner

The gate that catches this defect is the nvcc build of `tf-cuda-test`, and CI cannot run it: it needs nvcc,
and the host gate list (`compile-cuda-tests` without `-Dnvcc`) compiles the runner with
`kernels.available == false`, so `contract_tests.registered()` returns `error.BuiltWithoutKernels` before
the registrations are reached and their bodies are never semantically analysed. The `test-kernel-contract`
host step is blind the same way. CI's own record agrees: `grep -rn nvcc .github/workflows/*.yml` finds
only a comment (`no-gpu.yml:81`, that `check-pdl-loads` needs nvcc and is fixture-checked instead), and the
contract step CI runs is `zig build -Dfixed-cpu test-kernel-contract` (`no-gpu.yml:163`). So every change
that touches a CUDA contract registration needs the `-Dnvcc` build of the runner by hand, on a host with
the toolkit, before its image build is trusted; the image build itself (`fatbins install native` with
`-Dnvcc`) is the same gate at full cost.

