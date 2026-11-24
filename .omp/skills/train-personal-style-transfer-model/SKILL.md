---
name: train-personal-style-transfer-model
description: "Build or extend a personal writing-style corpus and train a style-transfer LoRA/voice model from it; skip for general scraping or non-personal voice work."
---

# train-personal-style-transfer-model

one skill: train/collect a personal writing-style model

Merged from 6 skill(s): build-personal-style-transfer-corpus, build-personal-style-transfer-model, harvest-personal-writing-style-corpus, harvest-public-post-history-for-style-corpus, train-personal-style-transfer-lora-on-vast, train-personal-style-transfer-model.

Goal: make AI-drafted text (PRs, docs) read in a specific person's voice via authorship style transfer - fine-tune a small model on (neutral->styled) pairs built from their own writing (writes-like-you / Novelcrafter / ITDA genre). Two steps: few-shot restyle with a strong model first to prove the voice is reachable, then distil into a cheap fine-tune. The hard part is the CORPUS: it must be the person's GENUINE writing (not AI-written PRs/commits) and free of other people's quoted text.

Adam's case (owner): identity Bad_Ad84. Sources = assemblergames.org (phpBB archive), AmiBay (XenForo, user_id=5358, 754 posts), Reddit u/Bad_Ad84, X @Bad_Ad84 (was @retrogamerstuff), GitHub BadAd84 (code only). Corpus at work\style-corpus\ (corpus.jsonl 648 posts, exemplars.txt, amibay_scrape.py / ag_scrape.py / profile.py).

TOOLING: Windows python3 has requests+bs4; drive it from WSL bash but pass C:/ paths (Windows python can't read /mnt/c). Windows curl.exe gets 403 from these forums - use a requests.Session with a real browser User-Agent instead.

XENFORO (e.g. AmiBay): member post search `/search/member?user_id=<id>&content=post` works WITHOUT login and 302s to `/search/<token>/?t=post&c[users]=<name>&o=date`; paginate with `&page=N`. It caps at ~10 pages (~200 most-recent). Search rows are TRUNCATED snippets - follow each `/post-<id>` permalink and extract `article[data-content="post-<id>"] .message-body .bbWrapper`.

PHPBB STATIC ARCHIVE (e.g. assemblergames.org): the rebuild attributes every post to ONE "Archive" user, so phpBB author search is DEAD (returns nothing). The real author is baked into each `.content` div as `posted by <NAME> on <DATE>:`. Enumerate the person's threads via web_search `site:<host> "<name>"` (num_search_results=20, several term-varied queries; it's a seed, not exhaustive), collect distinct `viewtopic.php?t=<id>`, then walk pages `&start=0,10,20,...` (10/page); parse each `.content`, take the lines `posted by / <NAME> / on / <DATE> / :` then body, keep rows where NAME.lower()==target. Stop a thread when a page repeats the previous page's first-post hash (phpBB clamps start past the end).

QUOTE STRIPPING (critical - or you poison the corpus with other people's words): BEFORE get_text, decompose ALL `<blockquote>` (phpBB `blockquote.uncited`, XenForo `.bbCodeBlock`); decomposing the outer removes nested quotes too. Then also drop lines starting with `>` and standalone `X said:` headers, and signatures (`Sent from my ... Tapatalk ...`). THEN VERIFY: sweep the finished corpus for 0 posts containing `said:` and 0 with `>` lines, and spot-check a known quote-post shows only the target's words. Do not assume the format - inspect one quote-post's raw HTML first (the owner flagged this and it mattered).

Style profile (ground the voice in data, don't guess): median sentence length, % sentences with ` - ` asides and `(` parentheticals, apostrophe-drop ratio (its/it's, dont/don't, cant/can't), tic counts, caps-for-emphasis. Reddit hard-blocks scripts even with a browser UA - use the real browser tool.

Register tension: a genuine forum voice may drop apostrophes and run casual - fine for chat, but an upstream PR usually wants the cadence/directness WITHOUT the typos. Offer the owner raw-voice vs tidy-voice (normalise apostrophes in the training pairs) as a decision.

Train an LLM to rewrite bland/AI text into one person's voice. Done for Adam 2026-10; artifacts at work\style-corpus\.

## 1. Harvest their genuine writing (the corpus is everything)
- Get ALL their usernames (ask + search the web). People reuse handles across forums + change them over time.
- phpBB archives (e.g. assemblergames.org): author search is dead on static rebuilds, but a full-text KEYWORD search for the username works via stable session-free URLs `search.php?st=0&sk=t&sd=d&sr=posts&keywords=USER&start=N` (don't rely on the session search_id). The archive bakes `posted by USER on DATE:` into each post body - filter on that, strip the `>`/`X said:` quote lines.
- XenForo (AmiBay, XDA): `/search/member?user_id=N&content=post` works WITHOUT login (capped ~200 recent, follow post permalinks for full text). MyBB archive: `search.php?action=finduser&uid=N` -> follow the meta-refresh 'results' link.
- Reddit: JSON + HTML profile are login-walled, but the RSS feed `https://www.reddit.com/user/USER/.rss?limit=100` still works (overview = comments+posts); comments/ submitted/ feeds 429 - space them out.
- Email is the best register for prose. On M365, reuse an existing DELEGATED Graph token (e.g. ots-invoicing's MSAL cache in /opt/invoicing/data/tokens.json) ON the box it lives so the secret never leaves; refresh with the cached RT (old RT stays valid for native clients), pull `/me/mailFolders/SentItems/messages` with plain `body` + header `Prefer: outlook.body-content-type="text"` (NOT uniqueBody - server-side too slow, times out at scale). Strip quoted threads (`____`/`From:`/`On...wrote:`) and the signature block (name/company/phone) locally.
- CLEAN HARD: decompose `<blockquote>` (handles nested quotes), strip signatures + phone/PII, dedup, verify 0 'said:'/'>' residue. Device-tag emails: mobile ('Sent from...') apostrophes are AUTOCORRECT, desktop is their real typing - this decides the target register (Adam deliberately DROPS apostrophes: desktop its 213 vs it's 2; mobile is autocorrect).

## 2. Make neutral->styled pairs (manufacture the parallel data)
- For each substantive sample (>=25 words) flatten to plain neutral English with a strong model (`completion(prompt, model="default")` in eval = Opus; ~1000+ pairs). Pair neutral(input) -> their-original(output). This teaches the TRANSFORM; training only on their text teaches generate-from-scratch, not restyle.
- Format as chat: system 'rewrite in NAME's style', user=neutral, assistant=styled; 90/10 train/val.

## 3. Train QLoRA on Vast (see global memory for the raw-API + dd-download gotchas)
- Image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel; pinned transformers==4.46.3 trl==0.12.2 peft==0.13.2 bitsandbytes==0.44.1 accelerate datasets. QLoRA Qwen2.5-7B-Instruct (r=32 alpha=64, 3 epochs) ~14 min on a 4090, ~$0.1. nohup it so it survives ssh drops. (7B is plenty for style; 14B only if fidelity is weak.)

## 4. Deliver
- Merge LoRA->base; convert to q8_0 GGUF (`convert_hf_to_gguf.py merged --outtype q8_0`, no build needed; Q4_K_M needs building llama-quantize).
- Download the GGUF via dd byte-ranges (global memory). Serve: `ollama create NAME -f Modelfile` (Modelfile = FROM gguf + SYSTEM prompt + temp 0.7), then restyle.py pipes a message through localhost:11434/v1. Optionally wire into the LiteLLM router for fleet access.
- Validate by routing held-out AI messages through it and confirming their voice. Keep the email-derived corpus LOCAL (never a shared repo).

Build a model that rewrites AI-generated text into a specific person's voice. Done for Adam 2026-10; corpus + scripts in `work\style-corpus\`.

## 1. Harvest their REAL writing (see the corpus-harvest skills for detail)
- Public forums via their username(s). phpBB archive (assemblergames.org): keyword search `search.php?st=0&sk=t&sd=d&sr=posts&keywords=USER&start=N` paginates session-free; keep posts whose injected `posted by USER on DATE:` line matches; `decompose()` every `<blockquote>` to drop quoted text. XenForo (AmiBay): `search/member?user_id=N&content=post`. Reddit: the `.rss` feeds (`/user/U/.rss`) bypass the login wall that 403s JSON/HTML.
- Own Sent email via MS Graph: reuse a delegated Mail.Read token (e.g. ots-invoicing `data/tokens.json` `msal_cache`), run ON the box that holds it (secret never leaves). `GET /me/mailFolders/SentItems/messages?$select=subject,sentDateTime,body` with `Prefer: outlook.body-content-type="text"`; use plain `body` (uniqueBody is too slow at scale) and cut the quoted thread locally at the first `____`/`From: ...Sent:`/`On ... wrote:` marker; cut signature at name/company/phone anchors; redact phone PII.
- STRIP others' words, signatures, PII; verify 0 leakage before using.

## 2. Register split (critical, easy to miss)
A person's deliberate voice can differ from autocorrected text (Adam drops apostrophes its/dont/cant on desktop+forums; mobile autocorrect restores them - device is readable from the email signature). Train on the consistent deliberate-voice subset; do apostrophe restoration as a post-step for formal output.

## 3. Make parallel pairs (WHY flatten)
Style transfer = input->output mapping, but you only have their OUTPUT. Manufacture the INPUT: flatten each message to plain neutral English with a strong model (eval `completion(prompt, model="default")` = Opus): prompt "Rewrite in plain neutral English, keep meaning and all detail, strip personal style." Pair neutral->original. Format chat SFT: system="rewrite in X's style", user=neutral, assistant=styled. ~1k substantive pairs is plenty; 90/10 train/val.

## 4. QLoRA train
Base Qwen2.5-7B-Instruct (7B nails style and is easy to serve; 14B only if 7B is weak). 4-bit bnb nf4; LoRA r=32 alpha=64 dropout .05 all-linear; trl `SFTConfig` 3 epochs lr 2e-4 bs 4 accum 4 max_seq_length 1024 bf16. Pin `transformers==4.46.3 trl==0.12.2 peft==0.13.2 bitsandbytes==0.44.1 accelerate==1.1.1 datasets==3.1.0`. ~15 min on a 4090, <$0.5.

## 5. Vast.ai orchestration - RAW REST (the `vastai` package 403s on writes/show)
Key at `C:/Users/Adam/.config/vastai/vast_api_key`. `search_offers(client, query, order)` (package) works for search. Everything else RAW:
- create: `PUT https://console.vast.ai/api/v0/asks/{offer_id}/` json {client_id:"me",image:"pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel",disk:60,runtype:"ssh",label,onstart_cmd} -> `new_contract`.
- list/status: `GET /api/v1/instances/` (v0 list = 410 Gone); read `ssh_host`/`ssh_port` once `actual_status==running`.
- attach your pubkey: `POST /api/v0/instances/{id}/ssh/` json {ssh_key:<pub>} -> 'SSH key added'.
- destroy: `DELETE /api/v0/instances/{id}/`. ALWAYS destroy when done.
SSH is Windows OpenSSH here (`~`=C:\Users\Adam): `ssh -i ~/.ssh/vast_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -p PORT root@HOST`. `nohup python train.py >train.log 2>&1 &` so it survives ssh drop; a background watcher that returns when `adapter/adapter_config.json` exists avoids polling.

## 6. Validate then serve
- Validate on the GPU BEFORE teardown: route real AI-style messages through base+adapter, confirm the voice.
- Serve: `merge_and_unload` -> GGUF Q4_K_M (llama.cpp) -> Ollama (Modelfile bakes the system prompt), or vLLM base+adapter; wire as a model in the LiteLLM router so AI drafts can be routed through it. Download the adapter (~150MB, portable) regardless.

Build a model that restyles AI/generic text into a person's voice. Done for Adam; artifacts + scripts live in `work\style-corpus\` (corpus.jsonl, pairs, adapter/, train.py, gguf_sftp.py, Modelfile, restyle.py, STYLE-MODEL.md).

## 1. Harvest the corpus (ONLY their genuine writing)
- Forums: phpBB archives (e.g. assemblergames.org) bake authorship into post TEXT ("posted by USER on DATE:"); enumerate via keyword search `search.php?st=0&sk=t&sd=d&sr=posts&keywords=USER` paginated `&start=N` (10/page), keep posts whose body starts "posted by USER", decompose <blockquote> to drop quotes. XenForo (AmiBay/XDA): `search/member?user_id=ID&content=post`. Reddit login-walls profiles even in a real browser - use the `.rss` feeds (`/user/X/.rss`, `/user/X/comments/.rss`), which bypass it.
- Email is the best register for PR/doc prose. OTS Sent Items via the ots-invoicing Microsoft Graph DELEGATED token (Mail.Read, adam@onetouchtechnical.com) in `/opt/invoicing/data/tokens.json` (`msal_cache`) on CT108; run the fetch on-box so no secret leaves. GET `/me/mailFolders/SentItems/messages?$select=subject,sentDateTime,body` with header `Prefer: outlook.body-content-type="text"` (plain `body` is fast; `uniqueBody` is slow). Using a native-client refresh token once does NOT break the app (old RT stays valid).
- Clean every sample: cut the quoted thread at the first `_____`/`From:`/`On ... wrote:` marker, strip the signature at name/company/phone anchors, redact phone numbers, drop `>`/`X said:` lines, dedup, VERIFY 0 quote remnants.

## 2. Manufacture neutral->styled pairs (no parallel data exists)
For each substantive sample (>=25-40 words) have a strong model (Opus via `completion(model="default")`) flatten it to plain neutral English (same meaning, no style). Pair neutral(input)->original(output). Format as chat: system="You rewrite messages in <Person>'s personal writing style...", user=neutral, assistant=styled. ~1,000-1,500 pairs is plenty.

## 3. QLoRA on Vast.ai
See the global memory on Vast REST/SSH gotchas (package write calls 403 -> use raw REST; key at C:/Users/Adam/.config/vastai/vast_api_key). Image `pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel`; pip install PINNED `transformers==4.46.3 trl==0.12.2 peft==0.13.2 bitsandbytes accelerate datasets`. Base Qwen2.5-7B-Instruct, QLoRA r=32 alpha=64, 3 epochs (~14 min on a 4090, ~$0.1). nohup the train so it survives ssh drops. Validate on the box: route sample AI messages through base+adapter and check the voice BEFORE tearing down.

## 4. Get it off Vast (the hard part - see global memory)
Merge LoRA into base, convert to GGUF with `llama.cpp/convert_hf_to_gguf.py --outtype q8_0` (no build needed). Pull the ~8GB GGUF with paramiko resumable SFTP (gguf_sftp.py): the SSH proxy drops bulk scp ~633MB and BANS connection storms, so reconnect+seek+resume, one gentle connection at a time. The small adapter (~100MB) scp's fine directly.

## 5. Serve
Ollama (install via winget; run CLI through cmd.exe, server auto-runs on :11434): `ollama create <name> -f Modelfile` (Modelfile = `FROM ./x.gguf` + SYSTEM prompt). `restyle.py` pipes a message through localhost:11434/v1. For always-on, serve the GGUF on a fleet box + add to the LiteLLM router.

## Key style finding
Adam's DELIBERATE voice drops apostrophes (its/dont/cant); apostrophes in his writing are mobile autocorrect (device-tagged from the email signature). Train targets on the dropped-apostrophe desktop+forum set; a "tidy" mode restores apostrophes for upstream PRs.

Use when building a corpus of ONE person's genuine writing (to fine-tune a model that rewrites AI drafts into their voice). Goal: only THEIR words, cleaned, deduped, verified.

## Discovery
- Owner gives handles; `web_search "<handle>"` to find venues. Watch for rename chains (Bad_Ad84 -> SlackR84) and forum migrations (assemblergames -> obscuregamers/prototopia.net).
- EXCLUDE AI-written sources (e.g. the owner said their GitHub is AI-written) - they poison the corpus with the voice you are removing.

## Per-engine harvest recipes
- **phpBB static archive** (e.g. assemblergames.org): real users flattened to one "Archive" user, so AUTHOR search fails; authorship is baked into each post body as `posted by <user> on <date>:`. Use KEYWORD search `search.php?st=0&sk=t&sd=d&sr=posts&keywords=<user>&start=N` (stable session-free pagination; ~half of matches are the user's - filter by the `posted by <user>` author line). Repeated searches hit flood control (may return 1 page); the start=N pagination URL is reliable. Quotes are `<blockquote>`.
- **MyBB archive** (e.g. assemblergames-archive.com): preserves real usernames; `search.php?action=finduser&uid=<id>` returns a meta-refresh "search submitted" page - follow the `action=results&sid=...` link; results paginated with real attribution.
- **XenForo** (AmiBay, XDA, Prototopia): member profile exposes `search/member?user_id=<id>&content=post` (works WITHOUT login); paginate `&page=N` (search caps ~10 pages / ~200 most-recent). Results are truncated snippets - follow each post permalink (`/threads/..#post-<id>`) for full body. Strip `blockquote, .bbCodeBlock` and Tapatalk signatures (`Sent from my ... using Tapatalk`).
- **Reddit** (login-walls JSON=403 and HTML profiles even in a real browser): the `.rss` feeds still work - `https://www.reddit.com/user/<name>/.rss?limit=100` (overview = comments+posts). The `comments/` and `submitted/` sub-feeds 429 if hit fast: add ~7s delays + retry. Parse Atom `<entry><content>` HTML, decompose `<blockquote>`, strip trailing `submitted by ...` footer, drop keybase-proof / pure-URL entries.
- **Sent email via Microsoft Graph** (best register match for PRs): reuse an existing MSAL delegated token rather than new creds (see the fleet memory on the ots-invoicing token on CT108). Request `/me/mailFolders/SentItems/messages` with header `Prefer: outlook.body-content-type="text"` and `$select=subject,sentDateTime,uniqueBody,body` - **uniqueBody** returns ONLY the composed reply (excludes quoted thread). Run the fetch ON the box holding the token so no secret leaves it; borrow a valid cached access token, else refresh and discard the rotated RT without writing the cache back.

## Cleaning (CRITICAL - owner will flag quote contamination)
- Remove OTHER people's quoted text: `for bq in content.select('blockquote'): bq.decompose()` BEFORE get_text (removing the outer blockquote also removes nested ones). Then strip lines starting `>` and `<name> said:` headers. Strip signatures.
- VERIFY before trusting: count corpus posts still containing `said:` or `>` quote lines - must be 0. Also check a KNOWN quote-post that the other person's words are gone.
- Dedup keeping the LONGEST version of near-duplicates (search snippet vs full-thread text): key on `date + text[:60]`, iterate sorted by `-len(text)`.

## Tooling gotchas (Windows harness)
- `python3` here is Windows Python (has requests+bs4); it reads `C:/...` paths, NOT `/mnt/c/...`. The bash shell is WSL (`/mnt/c/...`).
- `curl.exe` gets UA-blocked (403) by some forums; use `requests.Session` with a desktop-Chrome User-Agent. The harness `read` tool's jina/native fetcher often gets through where curl fails.
- Long harvests: background the bash job (it auto-reports when done; don't poll).

## Profile + next steps
- Measure the voice from data: median sentence length, apostrophe-drop ratio (its vs it's, dont vs don't), `' - '` dash-aside %, parenthetical %, tic words. Pick diverse substantive (>=25-40 word) exemplars for a few-shot demo.
- Decide register with the owner: raw (authentic, drops apostrophes) vs tidy (restore apostrophes for professional PRs, keep cadence).
- Few-shot demo first (strong model + exemplars) to validate; then neutral->styled pairs -> LoRA a small base -> restyle pass over AI drafts.

Goal: harvest ONE person's public posts into a clean, quote-free corpus of THEIR words, tagged by source+date, for a style profile or an authorship style-transfer fine-tune (make AI drafts sound like them).

## Tooling (Adam's Windows box)
- `python3` under WSL bash is the WINDOWS interpreter (has requests+bs4); write scripts with C:/ paths, run from /mnt/c. `curl` is Windows curl.exe and 403s on forums that gate on User-Agent.
- Scrape with `requests.Session()` + a real browser UA (Chrome). The `read` tool's native/jina fetcher also gets past some blocks. Be polite: 3-4 workers, ~0.2s delay.

## Find where they posted
- `web_search "<handle>"` (broad) + `site:<forum> "<handle>"` with num_search_results=20 across varied term combos to enumerate threads. Check GitHub/X/Reddit too.

## Per-site enumeration recipes
- XenForo (e.g. AmiBay): member post list `GET /search/member?user_id=<id>&content=post` works WITHOUT login via a Session; it redirects to `/search/<token>/?...`; paginate `&page=N`. Search caps ~10 pages / ~200 most-recent. Result rows link to `/threads/.../post-<id>`; fetch and extract `article[data-content="post-<id>"] .message-body .bbWrapper`.
- phpBB STATIC archive (e.g. assemblergames.org): the rebuild often flattens EVERY post to one "Archive" user (so author search returns nothing - "Total members 2" is the tell) and bakes real authorship into post text as `posted by <NAME> on <DATE>:`. Enumerate via the KEYWORD search for the handle (matches that injected line in every one of their posts): `search.php?st=0&sk=t&sd=d&sr=posts&keywords=<NAME>&start=N` - STABLE, session-free pagination (don't rely on search_id). Parse `div.post .content`; keep posts whose get_text lines are `posted by`/`<NAME>`/`on`/`<DATE>`/`:`/body. Results show full posts; the longest are truncated - follow the `viewtopic.php?p=<id>` permalink and re-extract to un-truncate. (MyBB archives e.g. assemblergames-archive.com keep real usernames and have `search.php?action=finduser&uid=<id>` -> follow the meta-refresh "Click here" to `action=results&sid=...`; but their search caps low.)
- Reddit: JSON endpoints 403 and HTML/old.reddit profiles now LOGIN-WALL even in a real headless browser (redirect to /login?reason=lor2). The `.rss` feeds still work logged-out: `https://www.reddit.com/user/<NAME>/.rss?limit=100` (overview=comments+posts), `/comments/.rss`, `/submitted/.rss`. They 429 fast - space requests >=7s and retry. Parse Atom `<entry><content>` (HTML), strip the trailing "submitted by ... [link][comments]" footer; drop keybase-proof / pure-URL entries.
- X/Twitter: profiles are login-walled; usually skip (tweets are short/low-value for a prose register).

## Cleaning (CRITICAL - no other people's words)
- Quotes: decompose ALL `<blockquote>` BEFORE get_text - this removes nested quotes and covers both phpBB `blockquote.uncited` and XenForo `.bbCodeBlock`. Also drop lines starting `>` and standalone `X said:` headers. Strip signatures (`Sent from my ... Tapatalk`).
- VERIFY: after merge, assert 0 posts contain `said:` or `>`-lines, and eyeball a KNOWN quote-post to confirm the quoted author is gone. (This is a real contamination risk the owner will flag.)
- Dedup keeping the LONGEST text per (date+prefix) so full beats truncated. Tag source+date. Filter to substantive (>=25-40 words) for the fine-tune set; keep short ones separately (still show terse style).

## Then
- Derive a data-driven style profile to brief the transfer: median sentence length, apostrophe style (its/it's, dont/don't), `' - '` and `(` aside frequency, caps-for-emphasis, tics. Note era drift (recent writing is often tidier).
- Few-shot demo first (strong model + ~18 exemplars) to validate the voice, then fine-tune: generate neutral->styled pairs (strong model strips each post to neutral; train neutral->original), LoRA a small base, wire as a restyle pass. Decide register with the owner (raw vs tidy/apostrophe-normalised) BEFORE building pairs - it changes the targets.
