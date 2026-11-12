# qwen3.8-flash-next-dev - repo rules, conventions, and gotchas

The Qwen3.8 Flash Next serve on spark4 as a development project: our layers on the MiaAI-Lab recipe, their tests and
benchmarks, and the upstream PRs. The hardware is ots-infra's; the GLM serve is glm5.3-flash-dev.

## Branches (owner 2026-11-12)
- **`production`** - the recipe the serve on spark6 runs today and the target to match or beat: the engine source its
  image was built from (TensorFold at `5c3e3e29`, the zmerge8 stack with the 64K boot fix; the build tar compared
  file for file) and, under `production/`, the image build, the launcher with its whole environment, the FP8 drafter
  overlay tool and the measured target. Frozen: production hotfixes only. Its history is unrelated to `main`'s, so
  read it in its own worktree (`git worktree add work/prod production`), never by switching this checkout.
- **`main`** - the in-flight work on the modern TensorFold engine: our levers as patches on an upstream release, the
  harnesses, the measurements. It follows upstream: on each release the series is re-seated
  (`scripts/qwen38/zig/target/reseat.py`) and every lever re-tested. When `main` matches or beats
  `production/SPEED-TARGET.md` at 1, 2, 4, 6 and 8 streams, production is retired and replaced from here.

## Layout
- `scripts/qwen38/` - the serve's files, AUTHORED here and COPIED to spark4 (`~/qwen-start.sh`, `~/qwen-ots/` for the
  image build, `~/work/` for the harnesses); the repo copy is the source. `scripts/qwen38/README.md` is the SSOT for
  the serve and each layer's evidence.
- `patches/1.2.6/` - EVERY change we own on TensorFold v1.2.6 (`6e9af9302`) as numbered `.patch` files applied in
  filename order to a PRISTINE upstream tree. The TensorFold source is never edited in place: the patches are the
  artifact and the build consumes them (`scripts/qwen38/zig/target/build_patches.sh TAG git://192.168.99.16/up-pr/tf
  6e9af9302 patches/1.2.6`). `patches/1.2.6/README.md` lists which patch carries which lever.
- `archive/tensorfold-levers124/` - RETIRED 2026-11-12: the old engine fork `ots/tensorfold-levers124`, kept whole as
  a git bundle (59 refs: the production zmerge8 engine source `27b6700cb`, the `archive/*` development tags, the
  working clone's branches) with a restore check. This repo is the only home of our Qwen work.
- The plain TensorFold fork for upstream PRs is GitHub `BadAd84/TensorFold` (branches cut from upstream main, one
  change each; nothing of this campaign lives there). It has no Gitea twin.
- `docs/` - the speed campaign and the upstream watchlist.
- `upstream/` - recipe PR packages; skill `submit-ots-patch-as-miaai-recipe-pr`.

## Conventions
- **On every TensorFold version bump, re-test the whole patch stack and retire what upstream absorbed (owner
  2026-11-11).** Bring our environment and our patches onto the new base first (``patches/` and `upstream/``), then decide every patch
  with evidence: apply it, run the gates (exactness, the suite, the A/B), and if the behaviour and the numbers hold
  without it, the patch is RETIRED: removed from the stack and recorded as superseded, naming the upstream commit that
  absorbed it. A patch that no longer applies is NOT automatically redundant; re-seat it, then test. Never carry a
  patch forward because it was there, and never drop one without the test.
- **Everything external arrives as .patch files (owner 2026-11-11).** A contributor's branch, an upstream PR's
  commits or our own delta against a pin is carried as numbered `.patch` files in a package under ``patches/` and `upstream/``, applied to
  a pristine checkout at a recorded base sha. Each package carries `RECORD.md` (repository, branch, sha, the base it
  applies to, and whether we edited the text), `SHA256SUMS`, and `apply.sh` whose `--check` writes nothing. Someone
  else's commits come from `git format-patch` verbatim, ours from `git diff`; never merge, rebase or cherry-pick into
  the base tree, and never edit it in place, so the gates and any A/B run against upstream's own source. A measurement
  taken on a patched tree names the base sha and the patches applied.
- **GPG-signed commits. Never `--no-gpg-sign`** (pinentry = YubiKey touch; if it fails, retry).
- **Current-state docs**; retired things marked RETIRED in one line; "current" claims carry a date.
- New `.sh` files need `git update-index --chmod=+x`.
- **A change ships only with replies byte-identical to the image it replaces** (golden 6/6:
  `~/work/qf_harness.py golden`, then `diff`), and its speed from an interleaved HTTP A/B on fixed prompts (3 passes
  an arm, the order alternating), never a single run: decode varies up to ~25% run to run on this box.
- **Every exact win ships, however small (owner 2026-10-09, glm5.3-flash-dev's rule, adopted 2026-10-10).** A change
  that is byte-identical (golden 6/6), passes its mutants and measures faster on its component ships, even when the
  serve-level gain is under the A/B noise: small wins stack. Below the noise an image is gated on golden 6/6 and no
  measured regression, not on a visible gain. Batch such changes into the next merged image; never park one as "too
  small to matter".
- **A speed number counts only if it was measured on the ARTIFACT that ships (owner 2026-10-09).** A lane's keep / drop
  verdict is timed with its patch built into an image by `build_zig_ots.sh` and served through the recipe's
  `start.sh` (the production entry point), interleaved with the base in one queued run (`zqueue.sh`, `merge/mverify*.sh`,
  `zab_rm.sh`); a dev-harness or kernel-bench number is a lead, never a verdict. A drop that rested on harness numbers
  alone is reopened until timed as an artifact.
- **Time to first token is a first-class metric (owner 2026-10-10: "it is how fast the model feels").** Every
  stock-vs-ours comparison and every image qualification on the Zig serve reports client-measured TTFT (to the first
  streamed content / reasoning / tool token: `scripts/qwen38/zig/bench/ttft.py`) for cold prompts at 1k / 8k / 32k /
  120k with thinking off and on, a warm +2k agent turn on a kept ~100k conversation, each idle and with 3 other
  streams decoding (one Spark, the recipe's Zig server). A change that slows TTFT is a regression even when tok/s
  improves.
- **RigMark is part of every benchmark (owner 2026-10-10).** Every stock-vs-ours comparison and every image
  qualification also runs RigMark (github.com/alexellis/rigmark, the DGX Spark community's shared benchmark; spark6
  `~/rigmark` at the commit in its `~/INVENTORY.md`) through `zab_rm.sh`: one comparison ID per sweep so the arms get
  byte-identical prompts, the extra body `{"reasoning_effort": "low"}` (RigMark's published card for this model family;
  `effort_check.py` proves the live server honours it), a fresh boot per arm, and a metadata.json that names the
  image, its OTS patch set and the drafter settings. Its JSON receipts and cards are kept in spark6
  `~/work/bench/rigmark/runs/`; published numbers use its cards. Our own probes (golden, `qf_run.py` decode, copy /
  prefill probes, TTFT) stay alongside it.
- **Every speed result is reported at 1, 2, 4, 6 and 8 parallel streams (owner 2026-10-11; 1 and 2 restated
  2026-10-12).** The serve's concurrency is a production choice, not a property of the code: a change can win at 4 and
  lose at 8 (pool size, batch composition), and 1-2 streams is the everyday load. So every stock-vs-ours comparison,
  image qualification and patch A/B measures decode (aggregate and per stream, all slots busy), TTFT and the pool size
  at boot at 1, 2, 4, 6 and 8 concurrent slots, one fresh boot per setting, same interleaving rules; tables carry a
  concurrency column. Adding high-concurrency rows never drops the low ones: a 4/6/8-only run (2026-10-12, zmerge8)
  had to be extended. A change faster at some levels and slower at others is a trade, not a keep: confirm the losing
  cell (ABBA), try gating it on the live stream count, and otherwise take it to the owner (fleet rule in
  `~/.omp/agent/AGENTS.md`, "Local serve speed work").
- **No outside traffic during a benchmark (owner 2026-10-11).** sparkDash (CT111, `sparkdash.ots-int.net`,
  192.168.99.111) polls every Spark's `:8888`, and the LiteLLM router (CT105, .105) and agents send requests too:
  on 2026-10-10 both hit the GLM serve mid-A/B and spoiled a TTFT arm. So every benchmark, qualification or A/B on a
  serve: (1) stops sparkDash first, `ssh root@proxmox.ots-int.net "pct exec 111 -- systemctl stop sparkdash"`, and
  starts it again (`... systemctl start sparkdash`) when the box is restored, from an EXIT trap so a failed run cannot
  leave it off; (2) firewalls `:8888` on the API box to localhost, the fabric and docker (copy spark1's
  `~/fw8888.sh on|off`; sudo needs `ssh -A`), lifted at the same point; (3) records `/health` request counts before
  and after each probe, and an arm with requests it did not send is rerun.
- **Thermal soak is a benchmark confound on GB10 (measured 2026-10-24).** Sustained load sags clocks
  ~4% in 50 s (2330-2370 -> ~2250 MHz) and settles ~2170-2200 MHz at 80-83 C with no throttle bits
  set: the same code on a hot box reads up to ~4-6% low. Interleave arms (already the rule), keep
  warm-ups short and identical, record the GPU temp at the start of every timed window, and never
  compare runs from differently-hot boxes. `nvidia-smi -lgc` above the natural curve is a no-op
  (never exceeded ~2275 MHz) - not a speed lever. Full envelope + rules:
  docs/GB10-THERMAL-BENCHMARK-METHODOLOGY.md.

- **The shared GPU lock can GHOST-LOCK, and the mechanism is known** (root-caught 2026-11-09, spark6):
  a runner that does `exec 9>gpu.lock` and then forks children (docker build, a boot) leaves the lock
  alive in ANY surviving child after the runner dies - `/proc/locks` shows a dead creator pid and every
  waiter queues forever. Pattern fix for runner scripts: scope the lock as
  `( flock 9; ... ) 9>lock`, or `exec 9>&-` before long-lived children. Exorcism if it happens
  (done once, preserved as `gpu.lock.ghost-2093720`): `mv` the lock aside, `touch` a fresh one, kill
  the stranded waiters (their runners relaunch), FIFO re-queue. Also on that box: the tf.kernels label
  gate is generation-split (`present` for e1f564e/364f21a-era start.sh, `embedded` for fd3f43e) -
  `~/work/lanes/fp4port/relabel.sh IMAGE TOKEN` fixes a mismatch in 5 s; and the zmerge8-kfix image's
  restore is `~/qwen6-start-prod.sh` (the fd3f43e recipe arg-check rejects `--kv-cache`).

- **The recipe's `stop.sh` STOPS AND REMOVES the container by name** (corrected 2026-11-09 after a
  wrong attribution): the two production-container destroys (07:48, 08:27) were HangVerify0050's own
  documented verify0050 flow - "Stopped and removed qwen38-flash-next-tf". That is by design: the
  recipe's `start.sh` line 178 recreates the container from nothing (`docker run -d --name`), so any
  window that stops the serve for its boot test must restore via `qwen6-start.sh` (which calls it),
  never `docker start`. Hygiene rules that stand: no label/ancestor/wildcard container cleanup
  (the arm images share the production image's label), no `docker system prune` while any lane works,
  and ASK THE ACTOR before attributing a destroy to a rogue filter - `docker events
  --filter type=container --filter event=destroy` gives the timeline, the lane's own script output
  gives the confession.

## Contributing upstream (`ashhart/TensorFold`)

The same text is in the three serve repos (GLM Zig, Qwen3.8 Flash Next, DeepSeek-V4.1). It was written 2026-11-12
from upstream `main` at `000b534a2`: `CONTRIBUTING.md`, `AGENTS.md`, the README's "Contributing with agents",
`docs/atc/SKILL.md`, `docs/pr/SKILL.md`, `docs/recipes/SKILL.md`, `.github/pull_request_template.md` and
`tools/pr_check.py`. Those files are the rules and they move: fetch upstream and read them at its tip before each
contribution (`git fetch https://github.com/ashhart/TensorFold.git main`), and when they change, change this
section in all three repos. The order of work is also in `.omp/RULES.md`, which omp carries on every request and
gives to subagents; they do not get this file, so hand them this section when upstream work is delegated.

**The order of work. Nothing is edited for upstream before step 3 returns a claim.**

1. **An issue first, always.** Upstream requires one before a new model family, backend or arithmetic change, "so
   we can agree on its gate" (a gate we proposed is not an agreed one). We open or find one for every change,
   because the ATC claim, the public session and the pull request's `Issue:` line all hang off an issue number.
   Blank issues are off: use the template that fits (`bug`, `feature`, `performance`, `proposal`). Look at the
   [agent radar](https://tensorfold.dev/atc) and `atc board --json` before choosing or opening one.
2. **Check it:** `atc check ISSUE --json`. Read `complete` first: `false`, or advice `incomplete`, means stop and
   resolve the missing coverage. Then by advice: `free` goes to step 3; `yours` means continue (`atc status --json`,
   `atc renew ISSUE`); `proposeInstead` means someone holds it, so offer to `pair`, `split` or `review` and wait for
   `accepted`; `takenOutside` or `notOpen` means do not start. A `duplicateAttempts` entry means others already have
   open pull requests for it: never add a competing one.
3. **Claim it:** `atc claim ISSUE --json`, and start only when it returns `claimed`. A successful new claim starts
   an anonymous public session on the radar and returns its `session` number: keep that number, do not start a
   second session, and check that `publication` is `public` (`unavailable` means the public update failed). For
   work already ours, `atc start ISSUE --json`. A draft pull request of ours that says `Fixes #ISSUE` also counts as
   the claim. The limit is 25 claims a user.
4. **While working:** `atc pulse ISSUE SESSION working --json` before each five-minute check-in expires
   (`reviewing` or `blocked` when that is the truth), and only while an agent is really working: never pulse for an
   idle one. `atc who FILE --json` after editing a file others may touch.
5. **When work stops:** `atc land ISSUE SESSION --json`; `atc release ISSUE --json` when we give the issue up.
6. **Before the pull request, and again after every push:** rebase on current `main` first, then
   `atc overlap --json` last. Every `"conflicts"` entry is resolved (coordinate, narrow or rebase) and the result,
   its time and its base go in the description. A conflict whose only shared file is `CHANGELOG.md` is the ordinary
   case; say so.

**What a pull request is.**

- One behaviour, cut from upstream `main` (its only branch), on a branch of the plain fork `BadAd84/TensorFold`. If
  the one-sentence description needs "and", split it; stack dependents as drafts and say what each sits on.
- From these repos a lever goes up as its patch re-seated on upstream's tip, alone. Review and diff it against
  upstream `main`, never the fork's `main`, and quote that sha.
- Anything new defaults off, and a switch arrives with the code that reads it and a measured benefit. A new setting
  is read through `platform/environment.zig` (a rule in its table, then `read(T, name, default)`); a new `getenv`
  is a lean finding.
- Upstream takes no lossy weight or cache format and no mode that changes output tokens, even opt-in. Drafts are
  never turned off on an advertised path.
- Code is written for TensorFold, not copied from another engine; anything from elsewhere names its source and
  licence in the pull request.
- The template is filled on the pushed head, every line: a line that does not apply says "n/a" and why, and only
  the sections the template says to delete are deleted. `Fixes #N` only when it completes the issue, else
  `Refs #N`. An optimisation added, finished or dropped updates that family's cell in
  `docs/optimization-ledger.md`. Zig changes carry a bullet under `## Unreleased` in `CHANGELOG.md` naming the pull
  request (`tools/pr_check.py --pr NUMBER` looks for it).

**Checks on the head, as upstream's CI runs them.**

- `python3 tools/pr_check.py --base origin/main --pr NUMBER`: new lean and source-length findings are errors.
- Lean, base against head with the same checker, both counts reported and 0 new: the commands are in
  `docs/pr/SKILL.md` step 5 (a worktree at the merge base, the head's `lean_check.py` copied into it, then
  `lean_new.py`). One checker run twice from one tree always reads 0 new: the two file counts must differ. Source
  files stay at or below 600 lines; comments and docstrings are single lines of at most 120 columns and carry no
  measurements, history, reviewer or pull request references.
- `zig build test test-golden` (`test-cuda-host` is a subset, not a substitute), `zig fmt --check build.zig zig`,
  `git diff --check`. Each new test is shown failing before the change and passing after, and is reached by the
  step that was run.
- A new or changed GPU kernel registers with the kernel contract (`docs/kernel-contract.md`) with a planted control
  that fails as planted, and the pull request posts each backend's `SUMMARY` line and exit status.
- Read the head's CI: fix what we introduced, label the rest inherited, flaky or infrastructure. Check runs for a
  fork pull request live in the base repo.

**Receipts, for a change that can reach inference.**

- Main against our branch on the same machine, checkpoint and settings, posted before asking for a run on
  upstream's machines; token hashes equal on the default path. A loss is fixed or shown to be noise first.
- Exactness contracts at the same checkpoint and settings: drafted equals `"draft": false`, a resumed prompt equals
  a fresh one, concurrent equals solo, cancellation and reset leave the next request valid
  (`tools/bench_concurrent.py ... --levels 1,4 --alone --serial`).
- Decode before and after with `tools/bench_openai.py`; prompt speed cold with `tools/bench_cache.py --require-cold`
  and `--prompt-cache-gib 0`, at 2k, 8k, 32k and 64k where admitted. Alternate the arms when the difference is a
  few percent. No slower than main at one stream and at the widest admitted; with `--drafter` no slower than
  without it.
- Name the commit, Zig and toolchain, GPU, OS, RAM class, checkpoint revision and request parameters; attach the raw
  results. Platforms are named by chip or target, run and not run: unrun is not passed.
- A changed reduction order needs an independent FP64 reference for each affected projection class, worst
  per-column difference reported, prompt and decode separately.

**Identity, privacy and the branch.**

- Author and committer are the owner's public identity (`BadAd84`, the GitHub noreply address), commits signed.
  Check every outgoing commit: `git log --format='%an %ae | %cn %ce' origin/main..HEAD`. No AI co-author or
  "Generated with" line: a pull request whose commits carry one lands as new commits and shows as closed.
- No private email, machine name, internal host, local path, key or confidential data in the diff, the commits or
  a receipt. Read the whole outgoing tree and history before pushing.
- Never force-push a branch under review, not to follow `main` and not to fix CI: add a commit. Maintainers rebase
  at landing.

**What needs the owner (fleet rule, `~/.omp/agent/RULES.md` section 14).** Upstream's own text says creating an
issue, sending a pull request and uploading results need the human's authorisation. Here: issue text, pull request
titles and bodies, and every comment go through the style pipeline and are posted only after the owner has approved
the exact text. A request from the owner to work on an issue covers the ATC claim, pulses, landing and release for
it (ATC posts only the typed command). `--github-name` is used only if the owner says so; sessions are anonymous
otherwise.

**Mechanics on this workstation (each cost a round trip).**

- ATC needs Node 22.16 or later, git 2.38 or later and an authenticated `gh` (`BadAd84`): it runs on the laptop, not
  on a Spark. Install or upgrade to the version upstream's README names (0.9.4 on 2026-11-12):
  `npm install -g github:ashhart/ATC`; `atc doctor --json` on a new setup. Always pass `--json`.
- It needs a FULL clone of upstream: a blobless one reports `workingTreeUnavailable` and every conflict as
  `unknown`. WSL bash cannot start `npx.cmd`: run ATC from a `.cmd` file through `cmd.exe /c`.
- Push to the fork over SSH (the HTTPS token lacks the `workflow` scope), and keep Actions disabled in the fork.
- The skills hold the step-by-step: `contribute-pr-to-tensorfold-main`, `run-atc-overlap-for-tensorfold-prs`,
  `tensorfold-upstream-pr-gate`, `gate-public-pr-text-on-owner-approval`.

## Gate
- `scripts/check-patch-packages.sh` - every package dir that carries `.patch` files (walked to depth 3 under the
  roots in `scripts/patch-packages.list`) has `RECORD.md` and `SHA256SUMS`, and the hashes match. Packages written
  before the rule are listed in `scripts/patch-packages.allow` and skipped; `--strict` shows that debt, and each is
  brought up to the rule the next time it is touched.
- `scripts/check-python.sh` - pyflakes over `scripts/` and `upstream/`. GATES on syntax errors and undefined names
  only; style findings are INFO.

## Gotchas (each cost real time)
- `build_qwen_ots.sh` must build from LF files: five layer files once went into the image with CRLF (it strips CRs
  now).
- The n-gram tables page from disk on the Python engine: a cold boot measures slower than a warm one. A/Bs boot each
  arm from a cold table (`ple_evict.py`).
- A server that keeps prompts answers a repeated prompt from its cache: qf_run.py's prefill prompts repeat every pass,
  so cold prefill needs prompts new to the server (`prefill_fresh.py`; the Zig release answered a repeated 128k
  prompt in 0.31 s).
- spark4 is stock DGX OS on a 1 Gb/s LAN link; spark6 (the comparison box) is the same. Production restarts take
  ~2 min; the container restarts by itself after a reboot (`unless-stopped`).
- Nesting heredocs inside `ssh '...'` breaks quoting: write a script, `scp` it, run it (or base64 it).
- **Type-check a patched tree on the laptop before any box build (found 2026-11-12).** The tree's own
  `zig build compile-config-server -Dtarget=aarch64-linux-gnu` cross-compiles the real CUDA server (the Flash Next
  lane backend included) with no nvcc and no GPU, using the local Zig 0.17.0
  (`C:\Users\Adam\tools\zig-x86_64-windows-0.17.0\zig.exe`, run through `work/zigl.py TREE build ...`): about
  3.5 minutes cold, about 10 seconds to a first error. A box build is 7.5 minutes and a failed one silently drops its
  arms from a queued run, so every rung and every new patch is compiled here first. It checks types, not kernels:
  the `.cu` side still needs the box.
- **The upstream recipe's `scripts/config.sh` exports lever settings** (`~/work/lanes/rpr/recipe`, MiaAI `20e15e4`):
  `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1`, `PREFILL_TAIL=512`, `PROMPT_HC2=1`,
  `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE=1536`, `PROMPT_GEMM2=1`, `CONFIDENCE=-0.4` and more. A binary that knows a knob
  runs with it ON through this recipe whatever the code's default says, so an arm that means "lever off" passes the
  explicit `=0`, and a table states the environment it ran in.
- **A patch cut against an older tree can revert base lines silently.** Old 0022 deleted `self.pos0 = pos0` from
  `Pass.chunk`, the `prompt_last` store and 0017's MX128 default while adding its own feature; it applied cleanly and
  compiled. The window self-check (`window self-check: N of 2080` in the boot log, 1,176 when exact) is what shows
  it: read that line for every rung, and diff a ported patch's `-` lines against the base before trusting it.
