---
name: adam-style-voice-model
description: "Restyle text into Adam's personal writing voice (PRs, issues, public posts) via the adam-style model on CT 110, review the restyle, present for approval; and operate / retrain / redeploy that style-transfer model."
---

# Adam style-transfer model - use and maintain

A fine-tuned LLM that rewrites text into **Adam's** personal writing voice (not a summariser or
editor - it changes tone/phrasing and preserves meaning). Qwen2.5-7B-Instruct + a personal QLoRA
adapter, served CPU-only on Proxmox CT 110.

## Standard flow for ANY public text (owner 2026-10-11): AI -> Adam -> AI review -> approval

Every text that will be posted publicly under Adam's name (PR titles/bodies, PR/issue comments, review
replies, forum posts) goes through this pipeline automatically, without being asked:

1. **AI draft.** Write the text normally (plain English, no em-dashes, exact numbers, code names in backticks).
   Save it to a file (e.g. `work\<name>_draft.md`).
2. **Adam restyle.** Send the draft through the model (client below). Long texts: send section by section if
   draft + reply could exceed the model's 2048-token context (~1,500 words total is the practical limit);
   a 3,300-char PR body took ~6 minutes on CPU and fitted.
3. **AI review of the restyle.** Compare restyle against the draft line by line. Keep the voice; fix ONLY
   things the restyle broke. The recurring breakages (measured 2026-10-11/12 on PR bodies and comments):
   - **Meaning flips / wrong words:** "a slot turns every round" became "every turn"; an arrow "before -> after"
     inserted that reversed which side was better; "the fill finishes sooner" became "it all finishes faster".
     Check every sentence that states a cause or a direction.
   - **Reversed or garbled reasoning in technical "because" clauses (the worst one):** "rank 1 only knows whether a
     request is salted, not which salt" came back as "rank1 cant tell apart between a request being salted or not",
     the exact opposite; "only states both salted or both unsalted replace each other" became "salted states only
     wipe each other out". For any bullet that explains WHY, re-derive it from the draft and rewrite it in the voice
     if the restyle changed the logic; don't patch single words.
   - **Numbers:** must survive byte-for-byte (they usually do; ranges like "13-15s" became "13 or so"; check every one).
   - **Code identifiers lose backticks** (`_recycle`, `TF_GLM_*`, `moving()`, file paths); restore them. An unquoted
     `_name` or `a_b` starts italics on GitHub.
   - **Symbols / names mangled:** `PARALLEL=4` -> `PARALLEL_4`; "torch's" -> "torches"; "GitHub" -> "git hub";
     "RigMark" -> "rigmark"; "rank 0" -> "r0"; "kept-state" -> "kept_state"; stray brackets.
   - **Invented openers/closers:** "Oh, I see -" at the start; "Fwd commit" for "Follow-up commit". Remove.
   - **Duplicated or dropped sentences** (a summary line appeared twice).
   - **Lost counts / precision:** "Two changes" -> "More changes"; "PRs" -> "PR".
   - **Tone sharpened:** "poor trade" -> "terrible trade". Soften where it criticises someone else's work; flag
     it to Adam as a tone call rather than silently reverting.
   - The model drops the title line's precision too; keep the title from the draft unless Adam prefers.
   - **Formatting / layout (the final pass, always):** the model flattens structure, so after fixing the words,
     re-lay the text out for GitHub before presenting it. Measured 2026-10-11: a two-point correction came back
     as ONE dense block and was posted that way; the owner flagged it. Rules:
     - one idea per paragraph, a blank line between paragraphs; no paragraph over ~4 lines;
     - a lead sentence that says what the comment is (correction / update / question) on its own line;
     - several distinct facts or reasons -> a short bulleted list, not a run-on sentence;
     - numbers that compare options -> a small table (option | time | pool cost) rather than prose;
     - the ask or next step (what we're measuring, what we'd like from them) as its own final paragraph;
     - restore markdown the draft had (headings, numbered steps, tables, code blocks) if the restyle dropped it.
     Keep the voice and wording; change only line breaks, lists and tables. Show this formatted version for
     approval, not the restyle's raw layout.
   - **A self-referencing text moved to a new place:** text written for PR #3 but posted on #2 said "on top of #2";
     fix references when the posting location changes.

**The pipeline applies BEFORE posting, never retroactively (owner 2026-10-27).** Text already posted stays as
it is: do not go back and restyle existing PR bodies, comments or issues, even if they were written without
the pipeline. Fix the process, not the history. If a posted text is wrong on substance, correct that specific
claim with a normal reply (which itself goes through the pipeline first); do not rewrite it for voice.

4. **Present for approval.** Show Adam the FINAL text inline in chat (never a file link), plus a short list of
   what the review changed versus the raw restyle and why. Post only after Adam approves. Even a one-line added
   sentence goes through steps 2-4 before posting.

Do not route internal notes, code, commit messages to our own repos, or numbers-only tables through it.

## Client

```python
# work\restyle.py <in.md> <out.md>
import json, sys, time, urllib.request
src = open(sys.argv[1], encoding="utf-8").read()
body = json.dumps({"model": "adam-style", "messages": [{"role": "user", "content": src}], "stream": False}).encode()
req = urllib.request.Request("http://orca.ots-int.net:11434/v1/chat/completions", body, {"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=900) as r:
    open(sys.argv[2], "w", encoding="utf-8").write(json.load(r)["choices"][0]["message"]["content"])
```

Run it as a background job (a long text takes minutes). Send the raw text as the user turn - the restyle
system prompt is baked into the model.

## The endpoint

OpenAI-compatible endpoint on **the orca box** (`orca.ots-int.net`, Quadro P4000), model
`adam-style`: `POST http://orca.ots-int.net:11434/v1/chat/completions`. Docker container `adam-style`
from `~adam/adam-style` (Ollama pinned 0.40.3 for Pascal kernels). Since 2026-10-15: measured ~29 tok/s,
a restyle in seconds. The CT 110 CPU serve (192.168.99.110) is a COLD FALLBACK - STOPPED with `onboot 0`
(`pct start 110` to use it; same endpoint path and model name). A 5 s probe on CT110 timing out with
WinError 10060 means you hit the stale address - use the orca box (orca.ots-int.net).

The output is terse, de-jargoned, British spelling, lowercase "api/windows", drops some apostrophes
("its", "dont", "cant": acceptable, part of the voice), and does NOT append a sign-off. If it misbehaves
systematically, the fix is a **retrain of the corpus**, not a prompt tweak.

## Posting mechanics (GitHub)

- Post with `gh.exe pr comment <n> -R <owner/repo> --body-file <file>` (never inline `--body` with backticks).
- Edit a posted comment: `gh api -X PATCH repos/<owner>/<repo>/issues/comments/<id> --input <json {"body":...}>`.
- Pushing commits onto someone else's PR branch whose commits are also an open PR of ours makes GitHub mark OUR PR
  "merged by us"; add a one-line note there explaining it.

## Where everything lives

- **orca box** (`orca.ots-int.net`, 192.168.99.50): the LIVE serve since 2026-10-15. Docker
  container `adam-style` from `~adam/adam-style` (Ollama 0.40.3; its CUDA 12 runner is the one with
  Pascal kernels). ~29 tok/s measured, a restyle in seconds. Build recipe + deploy files: the
  `ots/adam-style` Gitea repo (`STYLE-MODEL.md`, `deploy/paperclip/` - dir name predates the box rename). Teardown manifest `~/INVENTORY.md`.
- **CT 110** (192.168.99.110, hostname `adam-style`): the old CPU serve, COLD FALLBACK (STOPPED,
  `onboot 0`; `pct start 110` to use). Ollama systemd service, model `adam-style:latest` (Q4_K_M,
  4.7 GB), `/root/adam/` has the Modelfile, source adapter, Q4 gguf, and a built `llama-quantize`
  (`llama.cpp/`, kept for fast requantizes). Teardown manifest `/root/INVENTORY.md`. Pinned to the host
  P-cores (`lxc.cgroup2.cpuset.cpus: 0-3` in `/etc/pve/lxc/110.conf`).
- **3090** (192.168.1.90, driven over memagent :5555): `C:\work\adapter_3090\` is the source LoRA
  (161 MB - the artifact to protect); `adapter_3090_v1` is the previous version. A fast fp16 GPU serve
  (`C:\work\servergo.bat` -> `style_server.py`, ~seconds/restyle) can be restarted if sub-second speed is
  ever wanted; off by default so the GPU is free.
- **Adam's PC**: `work\style-corpus\` - corpus, train/val pairs, training + deploy
  scripts, `STYLE-MODEL.md` (full writeup), `PLAYBOOK.md` (shareable build guide).

## How to retrain / redeploy

Whole pipeline is scripted in `style-corpus\`. To change the model (clean corpus, add data):

1. **Fix the data** - the targets are the `assistant` field of each pair in `train.jsonl`/`val.jsonl`.
   Run the fix *on the 3090 in place* via a small script pushed through memagent (avoids transferring the
   ~1 MB files over the buggy `put`).
2. **Retrain on the 3090** (GPU): `train_go.bat` runs `train_3090.py` (QLoRA r=32/a=64, 3 epochs, ~22 min,
   writes `adapter_3090`). Back up the old adapter first; **validate before deploying** (load base+adapter,
   test a few messages on the GPU serve).
3. **Redeploy to the CT**: `merge.py` merges adapter into the base on the GPU (**Ollama dropped runtime
   LoRA, so you MUST merge**), `convert_hf_to_gguf.py --outtype q8_0` -> GGUF, bridge the ~8 GB to the CT
   by HTTP, `llama-quantize --allow-requantize ... Q4_K_M`, then `ollama create adam-style -f Modelfile`.

## Gotchas (each cost real time)

- **Ollama removed runtime LoRA adapters (0.40+)** - the `ADAPTER` directive errors; merge into the base.
- **CPU inference is memory-bandwidth-bound** - a 7B reads its whole weight set per token, so a smaller
  quant (Q4) is the speed lever, not more cores. On the hybrid i5-1235U the CT MUST be pinned to the
  P-cores (cpuset 0-3) or the scheduler parks it on the slow E-cores.
- **2048-token context:** draft + restyle must fit; split long texts by section.
- **memagent `put` is buggy/intermittent** (over-reads the socket; documented in `ots/memagent`
  `docs/BUG-put-socket-desync.md`) - move big files by HTTP (serve from the 3090, download), run scripts
  in place, and push small files via base64 echo-append through `exec`.
- **Corpus cleaning: strip the trailing sign-off line** (the "Thanks," / "Cheers," above a signature) or
  ~half the email targets end in it and the model appends a sign-off to everything, PRs included.
- Keep the restyle **system prompt byte-identical** between training and serving.
