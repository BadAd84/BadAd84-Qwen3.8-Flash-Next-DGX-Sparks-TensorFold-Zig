# RESULT: the `TF_FLASHNEXT_READOUT_FUSE` GPU receipt on a GB10, and the nvcc gate the host list lacked

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

## The window

Main `5780a037c998c7f801b5a6f4400c5ba23b2a444b` (tree `f1506c076c66f8bc44f382b1599a96e6cc5162aa`) against
branch head `3daeec7dff9c8ee1441b68c1f95d5d08a012d66b` (tree `d9059a30c7c8e70a50177568d1ce4d12988121f7`),
on spark6's GB10 (sm_121), one window, one GPU. The lever is off on M and B0 and on only on B1; every
number below is parsed from this run's own files under `box/out/run/`.

### Images and trees

- `IMAGE [tensorfold-qwen38:fuse-m-5780a037] id=sha256:fb512a21b1debc3655563f4da50ff20e472883cab9f73b1a04ffbb81c2f6c0f7 created=2026-11-20T13:50:52.644345355Z kernels=embedded size=25174649820`
- `IMAGE [tensorfold-qwen38:fuse-b-3daeec7d] id=sha256:2ae4302c72ae876d0fe73ea1e6197a89f4dc04b7eab35608cbbece4b45b7abad created=2026-11-20T21:14:58.90164702Z kernels=embedded size=25176811012`
- `#8 [build 4/4] RUN echo "SOURCE 5780a037c998c7f801b5a6f4400c5ba23b2a444b" &&     echo "NVCC $(/usr/local/cuda/bin/nvcc --version | tail -2 | tr '\n' ' ')" &&     echo "ZIG $(/opt/zig/zig version)" &&     cd /tensorfold && /opt/zig/zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold       -j"$(nproc)" fatbins install native && test -x /opt/tensorfold/native/bin/tensorfold-native && echo "BUILD OK"`
- `#10 [build 4/4] RUN echo "SOURCE 3daeec7dff9c8ee1441b68c1f95d5d08a012d66b" &&     echo "NVCC $(/usr/local/cuda/bin/nvcc --version | tail -2 | tr '\n' ' ')" &&     echo "ZIG $(/opt/zig/zig version)" &&     cd /tensorfold && /opt/zig/zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold       -j"$(nproc)" fatbins install native && test -x /opt/tensorfold/native/bin/tensorfold-native && echo "BUILD OK"`
- `#10 0.110 SOURCE 3daeec7dff9c8ee1441b68c1f95d5d08a012d66b`

Trees: each `git archive` extract was checked blob by blob against `git ls-tree -r` of its commit before
any build; the build log's own lines are:


### The lever, read from the tree

- `zig/src/platform/environment.zig` registers exactly `0` or `1`: `TF_FLASHNEXT_READOUT_FUSE` with forms `"0 or 1 (default 0)"` and `TF_FLASHNEXT_READOUT_FUSED` (the merged #3413 lever) with forms `"0 or 1 (default 0)"`; the parser accepts only the exact texts
  `0` and `1` for a `.flag`, and an unset or blank value is the default. The recipe `config.sh` exports
  neither name, and no other read-out lever is exported on; every arm therefore passes
  `TF_FLASHNEXT_READOUT_FUSE=0` or `=1` and `TF_FLASHNEXT_READOUT_FUSED=0` explicitly.

### The environment each arm ran in

- 1/B0a: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 1/B0b: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 1/B1a: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 1/B1b: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 1/M1: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1
- 1/M2: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1
- 2/B0a: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 2/B0b: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 2/B1a: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 2/B1b: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 2/M1: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1
- 2/M2: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1
- 3/B0/off: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 3/B0/on: image fuse-b-3daeec7d lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/B0a
- 3/B1/off: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 3/B1/on: image fuse-b-3daeec7d lever 1, 29 TF_/TENSORFOLD_ settings; identical to 1/B1a
- 3/M/off: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1
- 3/M/on: image fuse-m-5780a037 lever 0, 29 TF_/TENSORFOLD_ settings; identical to 1/M1

- fuse-b-3daeec7d lever 0: 6 boots, 1/B0a, 1/B0b, 2/B0a, 2/B0b, 3/B0/off, 3/B0/on
- fuse-b-3daeec7d lever 1: 6 boots, 1/B1a, 1/B1b, 2/B1a, 2/B1b, 3/B1/off, 3/B1/on
- fuse-m-5780a037 lever 0: 6 boots, 1/M1, 1/M2, 2/M1, 2/M2, 3/M/off, 3/M/on

The full `TF_`/`TENSORFOLD_` environment of the three distinct arms (the other runs of the same image are
byte-identical to them, as the lines above state):

```
## 1/M1
TENSORFOLD_CUDA_KERNELS=native
TENSORFOLD_IMAGE_TOKENS=16384
TENSORFOLD_MAX_IMAGES=50
TENSORFOLD_MEMORY_RESERVE_GIB=9
TENSORFOLD_NO_UPDATE_CHECK=1
TENSORFOLD_VIDEO_TOKENS=16384
TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python
TENSORFOLD_VISION_WORKSPACE_MIB=2048
TF_FLASHNEXT_CONFIDENCE=-0.4
TF_FLASHNEXT_DRAFTS=6
TF_FLASHNEXT_DRAFT_AHEAD=1
TF_FLASHNEXT_GATHER_EARLY=1
TF_FLASHNEXT_GATHER_READ=pread
TF_FLASHNEXT_GDN_LANES=1
TF_FLASHNEXT_HEAD_PIECE=1536
TF_FLASHNEXT_HOST_DRAW_THREADS=7
TF_FLASHNEXT_KEEP_LATE=1
TF_FLASHNEXT_PREFILL_TAIL=512
TF_FLASHNEXT_PRODUCT_STREAMS=5
TF_FLASHNEXT_PROMPT_EXPERT_TILE_ROWS=256
TF_FLASHNEXT_PROMPT_GEMM2=1
TF_FLASHNEXT_PROMPT_HC2=1
TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1
TF_FLASHNEXT_READOUT_FUSE=0
TF_FLASHNEXT_READOUT_FUSED=0
TF_FLASHNEXT_SAMPLED_HEADS=1
TF_FLASHNEXT_SAMPLE_CAND=1
TF_FLASHNEXT_SHARED_SIDE=1
TF_FLASHNEXT_WARM_AHEAD=1
```
```
## 1/B0a
TENSORFOLD_CUDA_KERNELS=native
TENSORFOLD_IMAGE_TOKENS=16384
TENSORFOLD_MAX_IMAGES=50
TENSORFOLD_MEMORY_RESERVE_GIB=9
TENSORFOLD_NO_UPDATE_CHECK=1
TENSORFOLD_VIDEO_TOKENS=16384
TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python
TENSORFOLD_VISION_WORKSPACE_MIB=2048
TF_FLASHNEXT_CONFIDENCE=-0.4
TF_FLASHNEXT_DRAFTS=6
TF_FLASHNEXT_DRAFT_AHEAD=1
TF_FLASHNEXT_GATHER_EARLY=1
TF_FLASHNEXT_GATHER_READ=pread
TF_FLASHNEXT_GDN_LANES=1
TF_FLASHNEXT_HEAD_PIECE=1536
TF_FLASHNEXT_HOST_DRAW_THREADS=7
TF_FLASHNEXT_KEEP_LATE=1
TF_FLASHNEXT_PREFILL_TAIL=512
TF_FLASHNEXT_PRODUCT_STREAMS=5
TF_FLASHNEXT_PROMPT_EXPERT_TILE_ROWS=256
TF_FLASHNEXT_PROMPT_GEMM2=1
TF_FLASHNEXT_PROMPT_HC2=1
TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1
TF_FLASHNEXT_READOUT_FUSE=0
TF_FLASHNEXT_READOUT_FUSED=0
TF_FLASHNEXT_SAMPLED_HEADS=1
TF_FLASHNEXT_SAMPLE_CAND=1
TF_FLASHNEXT_SHARED_SIDE=1
TF_FLASHNEXT_WARM_AHEAD=1
```
```
## 1/B1a
TENSORFOLD_CUDA_KERNELS=native
TENSORFOLD_IMAGE_TOKENS=16384
TENSORFOLD_MAX_IMAGES=50
TENSORFOLD_MEMORY_RESERVE_GIB=9
TENSORFOLD_NO_UPDATE_CHECK=1
TENSORFOLD_VIDEO_TOKENS=16384
TENSORFOLD_VISION_PYTHONPATH=/opt/tensorfold/python
TENSORFOLD_VISION_WORKSPACE_MIB=2048
TF_FLASHNEXT_CONFIDENCE=-0.4
TF_FLASHNEXT_DRAFTS=6
TF_FLASHNEXT_DRAFT_AHEAD=1
TF_FLASHNEXT_GATHER_EARLY=1
TF_FLASHNEXT_GATHER_READ=pread
TF_FLASHNEXT_GDN_LANES=1
TF_FLASHNEXT_HEAD_PIECE=1536
TF_FLASHNEXT_HOST_DRAW_THREADS=7
TF_FLASHNEXT_KEEP_LATE=1
TF_FLASHNEXT_PREFILL_TAIL=512
TF_FLASHNEXT_PRODUCT_STREAMS=5
TF_FLASHNEXT_PROMPT_EXPERT_TILE_ROWS=256
TF_FLASHNEXT_PROMPT_GEMM2=1
TF_FLASHNEXT_PROMPT_HC2=1
TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1
TF_FLASHNEXT_READOUT_FUSE=1
TF_FLASHNEXT_READOUT_FUSED=0
TF_FLASHNEXT_SAMPLED_HEADS=1
TF_FLASHNEXT_SAMPLE_CAND=1
TF_FLASHNEXT_SHARED_SIDE=1
TF_FLASHNEXT_WARM_AHEAD=1
```

### The checkpoint

The receipt recipe's `CHECKPOINT=nvfp4` resolves to `nvidia/Qwen3.8-Flash-Next-FP4-Local` at revision
`b9ce18a6887e18c089fdea8509a33e63429a3300`, the box path
`/home/adam/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300`
(96 GiB, present). The production serve at :8888 runs a different recipe (`~/qwen-zig-prod`, the INT4
checkpoint) while it is up; all three arms here load the nvfp4 checkpoint through `~/work/lanes/rpr/recipe`.

### The kernel contract, on the device

Command: `/home/adam/work/fuse0018gpu/b/tf-cuda-test kernel-contract tf_qmmf_hcact tf_qmmf_upmix 'qmmf read-out'`

```
(filtered) SUMMARY 6 kernels: 6 pass gates 1-4, 0 fail, 0 known findings; 2 controls: 2 red as planted, 0 missed; 0 limit problems; gates 626 ms, limits 4 ms
```

The six kernels, gates 1 to 4:

```
PASS nonfinite cuda flashnext tf_qmmf_hcact_bf16_16 (the read-out down with the act, 16-row half tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_hcact_bf16_16 (the read-out down with the act, 16-row half tile): five runs byte-identical (688 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_hcact_bf16_16 (the read-out down with the act, 16-row half tile): 3 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_hcact_bf16_16 (the read-out down with the act, 16-row half tile): declares none sums
```
```
PASS nonfinite cuda flashnext tf_qmmf_hcact_bf16_32 (the read-out down with the act, 32-row tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_hcact_bf16_32 (the read-out down with the act, 32-row tile): five runs byte-identical (11696 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_hcact_bf16_32 (the read-out down with the act, 32-row tile): 3 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_hcact_bf16_32 (the read-out down with the act, 32-row tile): declares none sums
```
```
PASS nonfinite cuda flashnext tf_qmmf_hcact_bf16_64 (the read-out down with the act, 64-row tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_hcact_bf16_64 (the read-out down with the act, 64-row tile): five runs byte-identical (22704 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_hcact_bf16_64 (the read-out down with the act, 64-row tile): 4 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_hcact_bf16_64 (the read-out down with the act, 64-row tile): declares none sums
```
```
PASS nonfinite cuda flashnext tf_qmmf_upmix_bf16_16 (the read-out up and the four-stream mix, 16-row tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_upmix_bf16_16 (the read-out up and the four-stream mix, 16-row tile): five runs byte-identical (5440 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_upmix_bf16_16 (the read-out up and the four-stream mix, 16-row tile): 3 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_upmix_bf16_16 (the read-out up and the four-stream mix, 16-row tile): declares none sums
```
```
PASS nonfinite cuda flashnext tf_qmmf_upmix_bf16_32 (the read-out up and the four-stream mix, 32-row tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_upmix_bf16_32 (the read-out up and the four-stream mix, 32-row tile): five runs byte-identical (92480 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_upmix_bf16_32 (the read-out up and the four-stream mix, 32-row tile): 3 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_upmix_bf16_32 (the read-out up and the four-stream mix, 32-row tile): declares none sums
```
```
PASS nonfinite cuda flashnext tf_qmmf_upmix_bf16_64 (the read-out up and the four-stream mix, 64-row tile): the stated rule holds: every output byte equal to the launches it replaces, planted non-finite rows included
PASS repeat cuda flashnext tf_qmmf_upmix_bf16_64 (the read-out up and the four-stream mix, 64-row tile): five runs byte-identical (179520 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext tf_qmmf_upmix_bf16_64 (the read-out up and the four-stream mix, 64-row tile): 4 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
N/A  sums cuda flashnext tf_qmmf_upmix_bf16_64 (the read-out up and the four-stream mix, 64-row tile): declares none sums
```

The two planted controls, each failing its gate on the planted fault before the CONTROL line records that the gate caught it:

```
FAIL shapes control: tf_qmmf_hcact_bf16_32 rounding its rows toward zero before the divide: at 17x324x10240 its bytes differ from fn_hc_reduce_act after the qmmf lane's fp32 down's from byte 6
```
```
FAIL shapes control: tf_qmmf_upmix_bf16_32 gating its up rows before their bf16 rounding: at 17x10240x320 its bytes differ from fn_hc_dense_mix after the qmmf lane's bf16 up's from byte 44
```
```
CONTROL control: tf_qmmf_hcact_bf16_32 rounding its rows toward zero before the divide: red at shapes, as planted
```
```
CONTROL control: tf_qmmf_upmix_bf16_32 gating its up rows before their bf16 rounding: red at shapes, as planted
```

Each launch record against the device's own measurement:

```
PASS limits live qmmf read-out down with the act, 16-row half tile: 128 threads launched, the driver allows 128; 40 registers, 0 + 24576 shared bytes (recorded 40, 0)
```
```
PASS limits live qmmf read-out down with the act, 32-row tile: 128 threads launched, the driver allows 128; 56 registers, 0 + 49152 shared bytes (recorded 56, 0)
```
```
PASS limits live qmmf read-out down with the act, 64-row tile: 128 threads launched, the driver allows 128; 74 registers, 0 + 65536 shared bytes (recorded 74, 0)
```
```
PASS limits live qmmf read-out up with the mix, 16-row tile: 128 threads launched, the driver allows 128; 48 registers, 0 + 55296 shared bytes (recorded 48, 0)
```
```
PASS limits live qmmf read-out up with the mix, 32-row tile: 128 threads launched, the driver allows 128; 68 registers, 0 + 61440 shared bytes (recorded 68, 0)
```
```
PASS limits live qmmf read-out up with the mix, 64-row tile: 128 threads launched, the driver allows 128; 94 registers, 0 + 49152 shared bytes (recorded 94, 0)
```

### Decode, cache on, 32768/8

| invocation | prompt | streams | M1 | M2 | B0a | B0b | B1a | B1b | B0 | B1 | B1vB0 | tokens a round (mean, before / after per comparison) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| openai_t0 | fibonacci-raw | 1 | 72.9 | 72.5 | 72.2 | 72.1 | 72.7 | 72.5 | -0.8% level | -0.2% level | +0.6% level | 5.22 / 5.22; 5.22 / 5.22; 5.22 / 5.22 |
| openai_t0 | gpu-chat-no-think | 1 | 46.7 | 46.5 | 46.4 | 46.2 | 46.7 | 46.6 | -0.7% level | +0.1% level | +0.8% level | 2.81 / 2.81; 2.81 / 2.81; 2.81 / 2.81 |
| conc_t0 | chat | 1 | 46.5 | 46.4 | 46.4 | 46.2 | 46.6 | 46.5 | -0.3% level | +0.2% level | +0.5% level | 2.81 / 2.81; 2.81 / 2.81; 2.81 / 2.81 |
| conc_t0 | chat | 2 | 86.5 | 86.3 | 85.9 | 85.8 | 86.8 | 86.5 | -0.6% level | +0.3% level | +0.9% level | 2.51 / 2.51; 2.51 / 2.51; 2.51 / 2.51 |
| conc_t0 | chat | 4 | 156.2 | 155.6 | 155.3 | 155.4 | 156.0 | 155.7 | -0.4% level | -0.0% level | +0.3% level | 2.51 / 2.51; 2.51 / 2.51; 2.51 / 2.51 |
| conc_t0 | chat | 6 | 210.4 | 209.7 | 209.2 | 209.1 | 209.5 | 209.6 | -0.4% level | -0.2% level | +0.2% level | 2.51 / 2.51; 2.51 / 2.51; 2.51 / 2.51 |
| conc_t0 | chat | 8 | 257.4 | 256.3 | 255.9 | 256.1 | 256.4 | 255.6 | -0.3% level | -0.3% level | +0.0% level | 2.51 / 2.51; 2.51 / 2.51; 2.51 / 2.51 |
| conc_t0 | code | 1 | 72.9 | 72.3 | 72.1 | 72.1 | 72.5 | 72.5 | -0.7% level | -0.1% level | +0.6% level | 5.22 / 5.22; 5.22 / 5.22; 5.22 / 5.22 |
| conc_t0 | code | 2 | 139.0 | 137.7 | 137.4 | 137.0 | 138.0 | 137.6 | -0.8% level | -0.4% level | +0.4% level | 4.83 / 4.83; 4.83 / 4.83; 4.83 / 4.83 |
| conc_t0 | code | 4 | 243.8 | 242.0 | 241.3 | 241.0 | 241.9 | 241.3 | -0.7% level | -0.5% level | +0.2% level | 4.83 / 4.83; 4.83 / 4.83; 4.83 / 4.83 |
| conc_t0 | code | 6 | 308.7 | 306.8 | 306.6 | 306.1 | 306.2 | 305.7 | -0.5% level | -0.6% level | -0.1% level | 4.49 / 4.49; 4.49 / 4.49; 4.49 / 4.49 |
| conc_t0 | code | 8 | 373.2 | 372.1 | 370.7 | 370.3 | 370.7 | 368.9 | -0.6% level | -0.8% level | -0.2% level | 4.49 / 4.49; 4.49 / 4.49; 4.49 / 4.49 |

Decode verdicts (first pass; a flagged cell's rerun is noted beside it): B0: 0 faster, 12 level, 0 slower, 0 unmeasured; B1: 0 faster, 12 level, 0 slower, 0 unmeasured; B1vB0: 0 faster, 12 level, 0 slower, 0 unmeasured

Per-stream decode tok/s (bench_concurrent's per_stream_tps, median over streams):
| prompt | streams | M1 | M2 | B0a | B0b | B1a | B1b |
|------|---|---|---|---|---|---|---|
| chat | 1 | 46.5 | 46.4 | 46.4 | 46.2 | 46.6 | 46.5 |
| chat | 2 | 43.3 | 43.5 | 43.3 | 43.2 | 43.6 | 43.6 |
| chat | 4 | 39.7 | 39.5 | 39.5 | 39.4 | 39.6 | 39.5 |
| chat | 6 | 35.9 | 35.8 | 35.6 | 35.6 | 35.8 | 35.7 |
| chat | 8 | 33.1 | 33.0 | 33.0 | 33.0 | 33.0 | 32.9 |
| code | 1 | 72.9 | 72.3 | 72.1 | 72.1 | 72.5 | 72.5 |
| code | 2 | 69.7 | 69.5 | 69.4 | 69.3 | 69.7 | 69.6 |
| code | 4 | 62.5 | 62.1 | 62.0 | 61.8 | 62.1 | 61.9 |
| code | 6 | 53.4 | 53.1 | 53.1 | 53.0 | 53.1 | 52.9 |
| code | 8 | 49.0 | 48.9 | 48.8 | 48.8 | 48.7 | 48.5 |

| comparison | streams | cells | mean change | faster | level | slower |
|---|---|---|---|---|---|---|
| B0 | 1 | 2 | -0.51% | 0 | 2 | 0 |
| B0 | 2 | 2 | -0.73% | 0 | 2 | 0 |
| B0 | 4 | 2 | -0.54% | 0 | 2 | 0 |
| B0 | 6 | 2 | -0.44% | 0 | 2 | 0 |
| B0 | 8 | 2 | -0.45% | 0 | 2 | 0 |
| B1 | 1 | 2 | +0.04% | 0 | 2 | 0 |
| B1 | 2 | 2 | -0.05% | 0 | 2 | 0 |
| B1 | 4 | 2 | -0.28% | 0 | 2 | 0 |
| B1 | 6 | 2 | -0.41% | 0 | 2 | 0 |
| B1 | 8 | 2 | -0.55% | 0 | 2 | 0 |
| B1vB0 | 1 | 2 | +0.55% | 0 | 2 | 0 |
| B1vB0 | 2 | 2 | +0.68% | 0 | 2 | 0 |
| B1vB0 | 4 | 2 | +0.25% | 0 | 2 | 0 |
| B1vB0 | 6 | 2 | +0.03% | 0 | 2 | 0 |
| B1vB0 | 8 | 2 | -0.09% | 0 | 2 | 0 |

Rerun (one per flagged cell; a repeat of slower is a loss):
No decode cell was slower in the first pair, so no decode rerun was flagged.
Decode losses: 0

### Cold prompt (TTFT), cache off, 131072/4

| cold case | M1 | M2 | B0a | B0b | B1a | B1b | B0 | B1 | B1vB0 |
|---|---|---|---|---|---|---|---|---|---|
| cold2k-off | 1.009 | 0.982 | 0.992 | 0.987 | 0.976 | 0.972 | -0.6% level | -2.2% faster | -1.6% faster |
| cold32k-off | 15.055 | 15.163 | 15.118 | 15.174 | 15.143 | 15.126 | +0.2% level | +0.2% level | -0.1% level |
| cold64k-off | 30.672 | 31.028 | 30.921 | 31.029 | 31.037 | 30.985 | +0.4% level | +0.5% level | +0.1% level |
| cold8k-off | 3.781 | 3.740 | 3.718 | 3.716 | 3.727 | 3.744 | -1.2% faster | -0.7% level | +0.5% level |

Cold verdicts (first pass; a flagged case's rerun is noted beside it): B0: 1 faster, 3 level, 0 slower, 0 unmeasured; B1: 1 faster, 3 level, 0 slower, 0 unmeasured; B1vB0: 1 faster, 3 level, 0 slower, 0 unmeasured

Cold losses: 0

### Exactness

- B0 cache on concurrent: concurrent equals solo 42 equal, 0 unequal (unverified 0); drafted equals `"draft": false` 6 equal, 0 unequal
- B0 cache on drafts: 8 equal, 0 unequal of 8
- B0 cache on turns: resumed from cached prompt tokens [13, 16, 16, 13, 24, 18, 3406]
- B0 cache off drafts: 8 equal, 0 unequal of 8
- B0 cache off fresh: 7 equal, 0 unequal of 7 resumed replies against the fresh ones
- B1 cache on concurrent: concurrent equals solo 42 equal, 0 unequal (unverified 0); drafted equals `"draft": false` 6 equal, 0 unequal
- B1 cache on drafts: 8 equal, 0 unequal of 8
- B1 cache on turns: resumed from cached prompt tokens [13, 16, 16, 13, 24, 18, 3406]
- B1 cache off drafts: 8 equal, 0 unequal of 8
- B1 cache off fresh: 7 equal, 0 unequal of 7 resumed replies against the fresh ones
- M cache on concurrent: concurrent equals solo 42 equal, 0 unequal (unverified 0); drafted equals `"draft": false` 6 equal, 0 unequal
- M cache on drafts: 8 equal, 0 unequal of 8
- M cache on turns: resumed from cached prompt tokens [13, 16, 16, 13, 24, 18, 3406]
- M cache off drafts: 8 equal, 0 unequal of 8
- M cache off fresh: 7 equal, 0 unequal of 7 resumed replies against the fresh ones

- replies equal over the greedy cells (token hashes), B0a, B0b against M1, M2: 144 equal, 0 unequal, 0 unverified
- replies equal over the greedy cells (token hashes), B1a, B1b against M1, M2: 144 equal, 0 unequal, 0 unverified
- replies equal over the greedy cells (token hashes), B1a, B1b against B0a, B0b: 144 equal, 0 unequal, 0 unverified

Totals of the greedy token-hash comparisons: {"B0a B0b vs M1 M2": {"equal": 144, "unequal": 0, "unverified": 0}, "B1a B1b vs B0a B0b": {"equal": 144, "unequal": 0, "unverified": 0}, "B1a B1b vs M1 M2": {"equal": 144, "unequal": 0, "unverified": 0}}

### The six golden prompts

| prompt | M sha (first 16) | B0 sha (first 16) | B1 sha (first 16) |
|---|---|---|---|
| golden-0 | 5dd272b4f316b776 | 5dd272b4f316b776 | 5dd272b4f316b776 |
| golden-1 | 0820676ff224de47 | 0820676ff224de47 | 0820676ff224de47 |
| golden-2 | c3615efee8f95ba6 | c3615efee8f95ba6 | c3615efee8f95ba6 |
| golden-3 | 7e16128d83939c7f | 7e16128d83939c7f | 7e16128d83939c7f |
| golden-4 | 8d627ef24ee21b8f | 8d627ef24ee21b8f | 8d627ef24ee21b8f |
| golden-5 | a934c244755c66ae | a934c244755c66ae | a934c244755c66ae |

- M against B0: 6 of 6 identical, 0 different; the harness diff's last line: `6/6 identical`
- M against B1: 6 of 6 identical, 0 different; the harness diff's last line: `6/6 identical`
- B0 against B1: 6 of 6 identical, 0 different; the harness diff's last line: `6/6 identical`

### Pool size and the startup memory line, per boot

| boot | model GiB | streams at once | pool line | sequence pool | startup memory line |
|---|---|---|---|---|---|
| 1/M1 | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 1/M2 | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 1/B0a | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 1/B0b | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 1/B1a | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 1/B1b | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 2/M1 | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 2/M2 | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 26.9 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 2/B0a | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 2/B0b | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 2/B1a | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 2/B1b | 73.52 | 4 | 4.14 GiB each at a 131072-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.52 GiB; 4 streams at once, 4.14 GiB each at a 131072-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up  |
| 3/M/on | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 3/M/off | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 3/B0/on | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 3/B0/off | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 3/B1/on | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |
| 3/B1/off | 73.50 | 8 | 1.32 GiB each at a 32768-token window | - | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 73.50 GiB; 8 streams at once, 1.32 GiB each at a 32768-token window, of 27.0 GiB left after a 9.0 GiB reserve; prompts in passes of up t |

### Boots

| boot | image | ctx/par | lever | wall s | answered s | gpu at boot (C,sm W) | mem GiB |
|---|---|---|---|---|---|---|---|
| 1/M1 | fuse-m-5780a037 | 32768/8 | 0 | 37.06 | 37 | 42,2411MHz,11.28W | 113 |
| 1/M2 | fuse-m-5780a037 | 32768/8 | 0 | 37.01 | 36 | 61,2411MHz,14.16W | 113 |
| 1/B0a | fuse-b-3daeec7d | 32768/8 | 0 | 37.01 | 37 | 57,2411MHz,13.55W | 113 |
| 1/B0b | fuse-b-3daeec7d | 32768/8 | 0 | 37.01 | 37 | 61,2411MHz,14.00W | 113 |
| 1/B1a | fuse-b-3daeec7d | 32768/8 | 1 | 37.01 | 37 | 60,2411MHz,13.84W | 114 |
| 1/B1b | fuse-b-3daeec7d | 32768/8 | 1 | 40.04 | 40 | 61,2411MHz,13.98W | 114 |
| 2/M1 | fuse-m-5780a037 | 131072/4 | 0 | 37.04 | 37 | 61,2411MHz,13.97W | 113 |
| 2/M2 | fuse-m-5780a037 | 131072/4 | 0 | 37.02 | 36 | 69,2398MHz,15.74W | 113 |
| 2/B0a | fuse-b-3daeec7d | 131072/4 | 0 | 37.00 | 36 | 68,2398MHz,15.26W | 114 |
| 2/B0b | fuse-b-3daeec7d | 131072/4 | 0 | 37.03 | 37 | 69,2398MHz,15.73W | 113 |
| 2/B1a | fuse-b-3daeec7d | 131072/4 | 1 | 37.01 | 37 | 69,2398MHz,15.88W | 113 |
| 2/B1b | fuse-b-3daeec7d | 131072/4 | 1 | 37.02 | 36 | 69,2398MHz,15.87W | 113 |
| 3/B0/on | fuse-b-3daeec7d | 32768/8 | 0 | 37.02 | 36 | 56,2411MHz,13.39W | 113 |
| 3/B0/off | fuse-b-3daeec7d | 32768/8 | 0 | 36.99 | 37 | 57,2411MHz,13.50W | 113 |
| 3/B1/on | fuse-b-3daeec7d | 32768/8 | 1 | 37.04 | 36 | 56,2411MHz,13.36W | 113 |
| 3/B1/off | fuse-b-3daeec7d | 32768/8 | 1 | 37.01 | 37 | 59,2411MHz,14.05W | 113 |
| 3/M/on | fuse-m-5780a037 | 32768/8 | 0 | 37.02 | 36 | 69,2398MHz,16.00W | 113 |
| 3/M/off | fuse-m-5780a037 | 32768/8 | 0 | 37.00 | 36 | 58,2411MHz,13.66W | 113 |

### Failures, and what was not taken

- None: every exactness tally is N equal and 0 unequal, every greedy hash pair equal, every golden
  prompt identical across arms, every contract line PASS, and no decode or cold cell slower on its rerun.

The full `kernel-contract` run was not taken, by instruction: the filtered run above is the receipt.

### End state

Production `/health` after the window (the curl output recorded at the close):

```
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8888/health
prod /health 200 at 2026-11-20T23:18:55+00:00
--- docker ps
qwen38-flash-next-tf tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 Up 13 minutes
--- production.txt
prod /health 200 (start rc 0) 2026-11-20T22:49:34+00:00 probe 1
qwen38-flash-next-tf tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 Up About a minute
--- RUN-DONE
RUN-DONE 2026-11-20T22:49:34+00:00 rc 0 /health 200
--- run.log tail
DONE 2026-11-20T22:48:06+00:00
RESTORE start 2026-11-20T22:48:06+00:00
[stop.sh] No container named qwen38-flash-next-tf: nothing to stop
RESTORE prod_rc 0 /health 200 (probe 1) 2026-11-20T22:49:34+00:00 mem_avail 29 GiB
DONE 2026-11-20T22:49:34+00:00 rc 0 production /health 200
run_fuse exit 0 2026-11-20T22:49:34+00:00
```

sparkDash after the window:

```
active
```

GPU lock holders after the window (`pgrep -af 'flock .*gpu.lock'`):

```
pgrep -af "[f]lock .*gpu.lock":
1005619 flock -o -w 43200 /home/adam/work/gpu.lock env JB_LOCKED=1 bash /home/adam/work/SyncBench/scripts/run_journal.sh
3951001 flock -o -w 43200 /home/adam/work/gpu.lock env SB_LOCKED=1 bash /home/adam/work/SyncBench/scripts/run_sync.sh
```

Box scratch removal:

```
docker rmi tensorfold-qwen38:fuse-m-5780a037 tensorfold-qwen38:fuse-b-3daeec7d
Untagged: tensorfold-qwen38:fuse-m-5780a037
Deleted: sha256:fb512a21b1debc3655563f4da50ff20e472883cab9f73b1a04ffbb81c2f6c0f7
Untagged: tensorfold-qwen38:fuse-b-3daeec7d
Deleted: sha256:2ae4302c72ae876d0fe73ea1e6197a89f4dc04b7eab35608cbbece4b45b7abad
rmi rc 0
images with fuse-: none
containers with fuse-: none
rm -rf ~/work/fuse0018gpu
rm rc 0
ls: cannot access '/home/adam/work/fuse0018gpu': No such file or directory
prod /health 200
```
