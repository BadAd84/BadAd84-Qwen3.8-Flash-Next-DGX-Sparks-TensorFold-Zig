# qwen3.8-flash-next-dev - repo rules, conventions, and gotchas

The Qwen3.8 Flash Next serve on spark4 as a development project: our layers on the MiaAI-Lab recipe, their tests and
benchmarks, and the upstream PRs. The hardware is ots-infra's; the GLM serve is glm5.3-flash-dev.

## Layout
- `scripts/qwen38/` - the serve's files, AUTHORED here and COPIED to spark4 (`~/qwen-start.sh`, `~/qwen-ots/` for the
  image build, `~/work/` for the harnesses); the repo copy is the source. `scripts/qwen38/README.md` is the SSOT for
  the serve and each layer's evidence.
- `docs/` - the speed campaign and the upstream watchlist.
- `upstream/` - recipe PR packages; skill `submit-ots-patch-as-miaai-recipe-pr`.

## Conventions
- **GPG-signed commits. Never `--no-gpg-sign`** (pinentry = YubiKey touch; if it fails, retry).
- **Current-state docs**; retired things marked RETIRED in one line; "current" claims carry a date.
- **No em-dashes** - plain hyphen. Never `git add -A`; stage explicit paths. New `.sh` files need
  `git update-index --chmod=+x`.
- Secrets never enter this repo (or a prompt). Fleet auth is YubiKey/agent-based.
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

## Gate
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
