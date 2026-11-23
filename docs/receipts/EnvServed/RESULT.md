# EnvServed: the register and dev.env completed against the SERVED tree, the presence form decided, the conflict recorded

Written 2026-11-23. Every figure below is a line a command printed in this session; the command is named
beside it. Nothing was built, no GPU was taken, no box was contacted.

## 1. The served tree, and how it was identified

The dev env of record boots the r5 FP4 image, so the table it must cover is that image's tree, not the
newest tree in `work/`. Identification is by the tree's own manifest against the image's label:

| step | reading |
|---|---|
| the image the dev boot uses | `tensorfold-qwen38:qr-a-r5-1ece6e6db`, `sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063` |
| its tree label | `tf.tree.manifest b3de0046f8d34c355162d08f8e811d326c08a053e7c13fd4276b0392212cca57`, `tf.source 1ece6e6dbbc073582d50738ce8e73e3c3261a73b+r5-0001-0020` (`work/QRerun/RESULT.md` section 1) |
| the local copy | `work/QRerun/trees/fp4/src`: 12,622 files, no symlinks, no `.git` |
| its manifest | `python work/QRerun/in/mkmanifest.py work/QRerun/trees/fp4/src work/EnvServed/fp4.manifest` then `sha256sum`: **`b3de0046f8d34c355162d08f8e811d326c08a053e7c13fd4276b0392212cca57`**, 12,622 entries, equal to the image's label |
| its provenance | upstream main `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` (base tarball sha256 `5aedd735...`) plus the 20 `patches/main-1ece6e6db-r5` patches (`work/QRerun/RESULT.md` section 1) |

The tree the register had been measured against, `work/Int4Step5/tree`, is 13,001 files with manifest
`0d594375f50e71ee923a913e29c51eac757542cbef8878993bf7a07a14b994c6`; it is not any served image's tree.
That is the whole of the "78 of 78" error: the statement was true of a tree nobody served.

## 2. Coverage before and after

Both gates, against the served tree's `zig/src/platform/environment.zig`, scopes `flashnext,cuda,common`:

```
before: coverage: 95 settings in scope, set 78, missing 17, annotations 2, worklist markers 0     rc=1
after:  coverage: 95 settings in scope, set 95, missing 0, absent 1, annotations 2, worklist markers 0, passage-lost 0   rc=0
        dev-env: 0 setting(s) without a citation
```

The after line is with `--passes '^(TENSORFOLD|TF_FLASHNEXT)_'`, the recipe launcher's own name filter (section 4).

(`work/EnvServed/coverage-before.txt`, `work/EnvServed/coverage-after.txt`,
`work/EnvServed/dev-env-after.txt`.) The gate also printed, both times, the seven `dev.env` names that
are not rows of this table; each is now classified in `docs/ENV-REGISTER.md` (one read outside the
table through the `profile` enum, six with no reader in this tree).

Every stated value still parses under the tree's own validator semantics
(`work/EnvBoot/check_values.py --table <served tree> --dev dev.env --scopes flashnext,cuda,common`):
`values: rows 95 stated 84 refused 0`, rc 0. The 11 rows without a value are the 1 `unset` and the 10
blank-value rows, each a default the table's blank rule turns into unset.

## 3. The 17 settings added, with the served tree's own read sites

Each line in `dev.env` carries the read site and the evidence path; the evidence root is the served
tree, `work/QRerun/trees/fp4/src`.

| setting | value stated | read site in the served tree |
|---|---|---|
| `TF_FLASHNEXT_DRAFT_AHEAD` | 0 | `families/flashnext/cuda_knobs.zig:27`, `read(bool, ..., false)` |
| `TF_FLASHNEXT_DRAFT_ROW_MS` | 0 | `families/flashnext/cuda_round_costs.zig:55`, `read(f64, ..., 0)`, kept 0 unless a table is set (`:56`) |
| `TF_FLASHNEXT_FUSED_SPLIT` | 0 | `cuda_knobs.zig:78`, 0 columns for false |
| `TF_FLASHNEXT_GATHER_CACHE_MIB` | 256 | `cuda_knobs.zig:22` |
| `TF_FLASHNEXT_GATHER_DIRECT` | 1 | `cuda_knobs.zig:12`, `read(bool, ..., true)` |
| `TF_FLASHNEXT_GATHER_EARLY` | 0 | `cuda_knobs.zig:37` |
| `TF_FLASHNEXT_GATHER_LOCK_SCALES` | 0 | `cuda_knobs.zig:47` |
| `TF_FLASHNEXT_GATHER_LOG` | 0 | `cuda_knobs.zig:42` |
| `TF_FLASHNEXT_GATHER_READ` | 0 | `cuda_knobs.zig:7`, words 0 and pread parse to 0 and 1 |
| `TF_FLASHNEXT_GATHER_THREADS` | 128 | `cuda_knobs.zig:17` |
| `TF_FLASHNEXT_HEAD_PIECE` | 256 | `cuda_knobs.zig:62` |
| `TF_FLASHNEXT_PREFILL_TAIL` | 0 | `cuda_knobs.zig:32` |
| `TF_FLASHNEXT_PROMPT_GEMM2` | 0 | `cuda_knobs.zig:72` |
| `TF_FLASHNEXT_PROMPT_MX128` | 0 | `cuda_knobs.zig:57` |
| `TF_FLASHNEXT_PROMPT_SYNC` | 0 | `cuda_knobs.zig:52` |
| `TF_FLASHNEXT_READOUT_FUSE` | 0 | `cuda_knobs.zig:84` |
| `TF_FLASHNEXT_ROUND_MS` | blank (no table) | `cuda_round_costs.zig:43-51`; blank reads as unset at `platform/environment.zig:303` |

What a boot supplies over the file is now measured rather than guessed, and it is written into the file
where the other "not set here" notes live. Arm A's container env (`work/QRerun/box/out/QA/env.txt`)
carries 11 rows equal to `dev.env`, 10 different, and 9 names the file does not carry. The five that
`~/qwen-zig/scripts/config.sh` supplies through `${NAME:-...}` (`DRAFT_AHEAD=1`, `GATHER_EARLY=1`,
`GATHER_READ=pread`, `PROMPT_GEMM2=1`, `HEAD_PIECE=1536`; `HEAD_PIECE`'s line is quoted in
`work/SeriesFix/box/out/RESULT-BOX.md`) take `dev.env`'s value when it is sourced first, and the dev
launcher's env block adds `PREFILL_TAIL=512`. The other four of the ten (`MEMORY_RESERVE_GIB=9`,
`KEEP_LATE=1`, `WARM_AHEAD=1`, `DRAFTS_GREEDY=15`) come from the window's own block
(`work/QRerun/window.sh:69`) or the launcher. None of the ten is measured here, so `dev.env` keeps the
engine's default for each; that is the one behavioural difference this filling creates, and it is stated
in the file rather than left to be discovered.

## 4. The presence form: decided, implemented, probed

**Decision.** A presence-tested setting has exactly two honest forms, and the old bare `export NAME` is
neither:

1. `unset NAME`: real absence. `dev.env` is sourced into the launcher's process, so the name is gone from
   what the launcher and the recipe read.
2. `export NAME=<value>`: required where the served image's own ENV bakes the name, because Docker applies
   the image ENV at container creation and nothing in the shell removes it; `-e NAME=` passes a value, and
   for `TENSORFOLD_CUDA_KERNELS` a blank is taken as a folder name and refused
   (`docs/environment.md:116`, `cuda/aot.zig:15-22`).

`dev.env` therefore states `TENSORFOLD_CUDA_KERNELS=native` (in the enabler block) and
`unset TF_ROCE_GID_INDEX`; `register.env` carries `# image-baked TENSORFOLD_CUDA_KERNELS=/opt/...`,
which is what makes the `unset` form an error for that name.

**The probes.**

1. *The valueless form does not reach the container as absence: measured.* EnvBoot's dev boot sourced
   `dev.env`, the container ran on a captured kernel set, and the engine refused the shape before loading
   weights (`tensorfold: --kv-cache fp8 runs on Flash Next's own glue on one rank: serve it without --tp,
   --slide or TENSORFOLD_CUDA_KERNELS, or without --kv-cache fp8`, `work/EnvBoot/RESULT.md` section 2b).
   The engine only raises that with `captured != null` (`cuda_lanes_load.zig:33`).
2. *An explicit value reaches the container and overrides the image's: measured.* Every recorded container
   env of a boot that passes `native` shows `TENSORFOLD_CUDA_KERNELS=native` as the effective value
   (`docs/knob-receipt-2026-11-20/receipt/w1/boot.md` line 21; `work/KvTierDedup/ev/out/new/seed/env.txt`
   line 1).
3. *The shell half: measured here.* `env -i ... bash -c 'set -a; . <file>; set +a; ...'`
   (`work/EnvServed/absence-probe.sh`, output in `absence-probe.txt`, run under WSL bash):

   ```
   == a valueless export, name not inherited ==       TF_ROCE_GID_INDEX=<absent>
   == a valueless export, name inherited ==           TF_ROCE_GID_INDEX=3
   == the unset form, name inherited ==               TF_ROCE_GID_INDEX=<absent>
   == the real dev.env under a hostile parent ==      TF_ROCE_GID_INDEX=<absent> TENSORFOLD_CUDA_KERNELS=native
   ```

   So the valueless form is not merely inert: it passes a parent's value straight through, which is the
   mechanism the boot hit. `unset` clears it. And the real `dev.env` sources cleanly under `env -i`.

**How the env reaches the container, read from the recipe's launcher.** The brief asked for this and it
was the one question the repo could not answer, so it took one read-only ssh probe (spark6
`~/qwen-zig/start.sh`, the served launcher; no build, no GPU, nothing written). The passage is a loop:

```bash
ENV_ARGS=(-e HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}")
while IFS='=' read -r name _; do
  [[ "$name" == TENSORFOLD_API_KEY ]] && continue
  ENV_ARGS+=(-e "$name=${!name}")
done < <(env | grep -E '^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=' || true)
...
here_cmd=(docker run -d --name "$CONTAINER_NAME" ... "${ENV_ARGS[@]}" "${KEY_ARGS[@]}" ... "$IMAGE" ...)
```

So: only names present in the launcher's process environment are passed, each as `-e NAME=value`, and
only under the two prefixes. That settles all three parts of the brief at once. `unset NAME` reaches the
container as absence (no `-e`, so only the image's `ENV` could supply it). A valueless `export` generates
no `-e` at all, so the image's value passes through untouched, which is exactly the measured refusal. An
explicit value is passed as `-e NAME=value` and overrides the image's.

**The passage finding.** The filter also decides which of our settings can act: `dev.env` states 27
`TF_*` names (26 with a value, `TF_ROCE_GID_INDEX` as `unset`), and the launcher never passes those. All
26 are in the `explicit defaults` section, so each states the value the engine already uses: inert and
harmless today, and recorded in `docs/ENV-REGISTER.md`. To keep it from becoming a silent hole, the gate
now takes `--passes` and fails a value above the defaults marker that the filter cannot carry
(`PASSAGE-LOST`), reports a defaults-section one as an advisory, and fails a setting stated twice
(`DUPLICATE`). Proved on planted defects:

| planted defect | gate's answer |
|---|---|
| `TF_QWEN35_CHUNK_SOLO=8192` moved above the defaults marker | `PASSAGE-LOST TF_QWEN35_CHUNK_SOLO: the launcher cannot carry it into the container`, rc 1 |
| `TF_CACHE_EVICT` stated a second time above the marker | `DUPLICATE TF_CACHE_EVICT: the env states it more than once`, rc 1 |

**Checker and updater, updated and proven.** `check-env-coverage.py` now accepts `unset NAME`
(`--absent-pattern`), fails a bare `export NAME` as `NO-VALUE` (`--no-value-pattern`), reads
`# image-baked NAME=<value>:` from the register and fails `unset` of such a name as `IMAGE-BAKED`, and
prints the absence count in its summary. `check-dev-env.py` requires the same citation above an `unset`
line. `update-env-register.py` treats `unset` as carried, emits `# missing NAME=presence` for a reader
whose default is `null`, and normalises the read-site path it prints. Each gate was proved able to fail
on the real defect shape before the fix landed:

| planted defect | gate's answer |
|---|---|
| `export TF_FLASHNEXT_PROMPT_SYNC` (no value) | `NO-VALUE ...`, plus `MISSING`, rc 1 |
| `unset TENSORFOLD_CUDA_KERNELS` | `IMAGE-BAKED TENSORFOLD_CUDA_KERNELS: the served image bakes it (/opt/.../sm121)`, rc 1 |
| one line deleted | `MISSING TF_FLASHNEXT_ROUND_MS`, rc 1 |
| an uncited `export` and an uncited `unset` | `dev.env:1 ...`, `dev.env:2 TF_ROCE_GID_INDEX ...`, rc 1 |

`update-env-register.py` against the served tree reproduces `register.env` byte for byte (0 added to the
worklist, `diff` empty), and with one line removed it appends
`# missing TF_FLASHNEXT_KEEP_LATE=presence # ... read at families/flashnext/cuda_mtp_draft.zig`.

## 5. The fp8 conflict, recorded in `docs/ENV-REGISTER.md`

- `tensorfold-qwen38:qr-a-r5-1ece6e6db` and `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` bake
  `TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121` and ship that captured set
  (`docs/KNOB-SCREEN.md`; observed in force by the EnvBoot boot).
- A captured set is refused with `--kv-cache fp8` and with the page pool at TP=1
  (`cuda_lanes_load.zig:33,35`), so the documented dev shape (fp8, `TF_FLASHNEXT_KV_PAGES=4096`, 8 x
  262,144) cannot boot while the setting is absent. The shape is not fixable by any value of the setting
  other than `native` or a real captured folder.
- `native` clears `captured` (`cuda/aot.zig:17`) and both are admitted at TP=1. The shape's memory plan is
  the tier window's measured one at exactly this shape (`work/KvTierShip/RESULT.md` section 1, the
  `levels/off` control whose plan line ends `own glue kernels`): first stream 4.99 GiB in the model's,
  seven taking 278 pages of 4,096 rows (20.02 GiB) of the 31.0 GiB after the 10 GiB reserve.
- **The tier windows booted that shape for 30 cells because every cell's container env carried
  `TENSORFOLD_CUDA_KERNELS=native`**, passed explicitly (`work/KvTierDedup/ev/out/new/seed/env.txt` line 1).
  Nothing about their images differed. So the shape needs no image without the baked variable and no
  engine change; it needs the setting stated, which `dev.env` now does.

**Can fp8 at 8 x 262,144 boot on the r5 image?** Yes, with the setting stated as `native`, and the
captured-set refusal that stopped EnvBoot's boot is gone by construction. Two caveats, stated as they are:
the FP4 arm's own boot at that shape has not been taken (no GPU in this task), so the plan line on r5
itself is inference from the identical plan code measured on the tier build; and `native` means the
installed captured set is never loaded, so whatever speed it could give is unmeasured (A3 in
`docs/KNOB-COVERAGE.md`, recorded in the register as `debt`).

## 6. What changed in the repo

| file | change |
|---|---|
| `scripts/qwen38/zig/target/env/dev.env` | 17 served-tree settings added with read sites; `TENSORFOLD_CUDA_KERNELS=native` in the enabler block with the refusals it clears; `unset TF_ROCE_GID_INDEX`; the six recipe-supplied values recorded and their consequence stated |
| `scripts/qwen38/zig/target/env/register.env` | `image-baked` and `debt` annotations for the kernel set, `default-ok` for the `unset` form |
| `scripts/qwen38/zig/target/env/check-env-coverage.py` | `unset` form, `NO-VALUE`, `IMAGE-BAKED`, `DUPLICATE`, `PASSAGE-LOST`, absence count, `--absent-pattern`, `--no-value-pattern`, `--passes`, `--measured-before` |
| `scripts/qwen38/zig/target/env/check-dev-env.py` | the `unset` form needs a citation |
| `scripts/qwen38/zig/target/env/update-env-register.py` | `unset` counts as carried; `=presence` worklist lines; portable read-site paths |
| `docs/ENV-REGISTER.md` | the launcher's passage loop and what it decides; the presence forms and why the bare export was wrong, with the probe; the fp8 conflict record; the served-tree identity and the current coverage; the seven non-row names and the 26 unpassable defaults classified; the re-seat steps now start from the image's tree label and pass the filter |

Byte-level: all six files are LF and ASCII (`grep -qP '\r'` and `LC_ALL=C grep -P '[^\x00-\x7F]'` both
clean), and the three Python scripts pass `python -m py_compile`.

Three signed commits, all on `main` and unpushed: `c70f8d13` (dev.env, register, the three scripts and
this page's doc counterpart), `3cd24943` (the blank-rule citation pointed at the served tree's line
116), `e6fc009c` (the launcher's passage loop, `PASSAGE-LOST`, `DUPLICATE`).
