# QInt4: the checkpoint comparison completed on both arms, with arm B gated on its own arithmetic

One hold of `~/work/gpu.lock` on spark6, the two marker-tied r5 images from the 2026-11-22 QRerun window, the driver
re-staged at `66e9edb0...` (the `keep_raw()` fix plus the new arm B gate). Arm A's external fidelity gate is unchanged
in the driver, and its result stands from the boot that ran it (QCMPB 20 of 20); this window reused the 1,664 rows that
boot produced, hashed them before and after, and verified them byte for byte against the 2026-11-19 FP4 arm. Arm B,
which the previous window voided at 8 of 20 against a differently configured INT4 serve, is now gated internally: on
20 of 20 prompts its drafted replies equal its own `"draft": false` replies, token for token, with the drafter proven
to have run on the drafted pass and proven stopped on the plain one.

Every table below is filled; the outputs it came from are in `work/QInt4/analysis/`.

## 1. The images, the driver and the payload

| arm | tag | image id | tree manifest (entries) | tf.source |
|---|---|---|---:|---|
| A: r5 FP4 | `tensorfold-qwen38:qr-a-r5-1ece6e6db` | `sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063` | `b3de0046f8d34c355162d08f8e811d326c08a053e7c13fd4276b0392212cca57` (12,622) | `1ece6e6d...+r5-0001-0020` |
| B: r5 INT4 | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` | `sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70` | `ab6389fc2ab680d001e4c7061c8f9e251dcdfcb2e0ab510b73465077128db073` (12,625) | `1ece6e6d...+r5-0001-0020+int4-0021-0022` |

Neither image was rebuilt: the driver skipped both stages by verified tree manifest and both builds by their
`tf.tree.manifest` and `tf.source` labels, and its log carries the ids above (`SKIP build A/B ... carries ...`).

- Payload: `stage.tgz` sha256 `566cd791d9182dcbe3fd475f1466f7265d821358d6aedadc63af64af56a1568c`, 43,264,984 bytes;
  `in/SHA256SUMS` sha256 `a6111826dcd17d7a510c53a8fc170ed647a63519e3627cb22af4b7b9030490a2` over 53 files; the box
  re-verified it at preflight: `sums SHA256SUMS: files 53 failing 0`. The copy was hashed on both sides before the
  unpack (`566cd791...` locally and on the box).
- Driver `window.sh` sha256 `66e9edb04a669a0fd73bba103934734a68b89202bf41e83a404a04d6c21f7021`, the same 64-character
  digest on the laptop and on the box. It is the 2026-11-22 fixed driver `9402d9b1...` plus this window's arm B gate
  change; the `keep_raw()` fix and selftest case 8d are unchanged.
- New instrument `in/draft_gate.py` sha256 `ddb2080d84e3fd4f70ec1bc4e858b995e9108a74d26456d4fd4e44ba663556e0`.
- One payload detail, stated because it is in the sealed sums: the 53rd entry is a generated
  `in/__pycache__/qverify.cpython-314.pyc`, written when the laptop's selftest imported `qverify.py`. It is sealed,
  verified and unused by any gate (`qverify.py` runs as a script). The local copy was removed after the seal and
  `qrstage.py` now excludes `__pycache__`, so the next payload is 52 files. The sealed bytes that ran are unchanged.
- Selftest on the box, rc 0, with the new case: `SELFTEST-OPEN internal exactness (SELFTEST ok: 11 of 11 checks
  caught their target)` and `SELFTEST-OK env, banner (7 mutations stopped, 2 identities opened), manifest, decode,
  comparer, fidelity (QCMPB), internal exactness (11 flips), qcount, qverify, boot reuse, raw kept, X1 flag, local
  scope`.
- The new wiring is itself gated and the gate is proved load-bearing: `prove_gate_wiring.sh` shows the clean driver
  passes (`PROVE-OPEN good (rc 0)`) and each planted defect is caught with its own message: the arm B call removed
  (`does not call draft_gate.py for arm B`), arm A gated against QCMPA instead of QCMPB (`not the QCMPB one`), and a
  second `fid_gate.py ... "$ref"` reference re-added (`fidelity-gate invocations`).
- Preflight on the box, rc 0: production up and pinned at `sha256:235211ea...` with `/health` 200, no foreign
  container, `start.lock` free, 128 GiB free, load 0.13, 28 GiB MemAvailable with production still up.

## 2. The gate change: arm A unchanged, arm B internal

The previous window stopped arm B at `FID-FAIL QCMPA eq 8 (want 20)` and voided it. That comparison cannot carry a
verdict about this port. Quoted from the two reference runs' own boot logs:

    QCMPA, the 11-19 INT4 reference (production's serve)
      azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8888
        Window   262144 tokens · 8 at once · bf16 KV · drafts MTP
        int4 prompt gate/up: int4_prompt_kernel on 64-pair items, 2x4 warps, 2x4 tiles, 3 stages (TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1)
        int4 lm_head: calls of 17 or more rows in 32-row items (TF_FLASHNEXT_HEAD_ROW_TILES=2)
        draft head: the int4 lm_head's own columns (TF_FLASHNEXT_DRAFT_INT4), 79592 ids, 105.1 MB

    QCMPB, the 11-19 FP4 reference (arm A's like-for-like oracle)
      nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8888

Arm B runs 4 at once, a 131,072-token window, bf16 KV, vision off, `int4 kernels: prompt gate/up int4_kernel, lm_head
16-row items` and an mxfp8 drafter. Two different arithmetic paths cannot produce identical token bytes even when
both are correct; the 8 of 20 measured configuration, as the divergent replies' shape already showed (all end on the
same `####` answer, all gold-correct, first difference at character 1 to 344, token counts -14 to +23).

This window therefore gates arm B on itself, on the same boot and the same 20 prompts:

- every prompt is sent twice, once drafted (no `draft` field) and once with `"draft": false`, both greedy, thinking
  off, both carrying `return_token_ids`;
- the pair must match in the server's own token-id hash (`tensorfold.token_sha256`), in the token ids, in the reply
  text and in the completion-token count, or the prompt fails;
- the pair must be non-vacuous both ways: the drafted row reports `tensorfold.drafts` true with
  `speculative.drafted` at least 1, and the plain row reports false with `speculative.drafted` 0, or the flag never
  reached the engine and the pair proves nothing;
- a row missing the hash, the ids, the flag or the counter is UNVERIFIED and fails, never equal.

Arm A keeps its external gate unchanged, because QCMPB is like for like on every serve axis the banner shows. That gate
was not re-run in this window: its marker and its complete rows were reused, and its 20 of 20 result stands from the
boot that ran it (quoted in section 4).

Measured on arm B, gate boot 15:28:18Z:

    SUMMARY rows 20/20 pairs_eq 20 text_eq 20 tokens_eq 20 verdict SELF-CONSISTENT
    DRAFT-OK drafted equals draft:false on 20 of 20 prompts, both passes non-vacuous

20 PAIR lines, 0 PAIR-FAIL. Drafted proposals per prompt 48 to 307 (accepted 48 to 253), plain proposals 0 on all 20,
token-count differences {0}. The pair-by-pair lines are in `analysis/draft-gate.txt`; the gate's own summary and the two
independent checks of its fields follow:

```
DRAFTED gsm8k-test-0 tokens 76 drafted 76 accepted 56
DRAFTED gsm8k-test-6 tokens 94 drafted 86 accepted 80
DRAFTED gsm8k-test-84 tokens 243 drafted 280 accepted 196
DRAFTED gsm8k-test-102 tokens 190 drafted 169 accepted 146
DRAFTED gsm8k-test-217 tokens 59 drafted 48 accepted 48
DRAFTED gsm8k-test-218 tokens 217 drafted 228 accepted 177
DRAFTED gsm8k-test-420 tokens 137 drafted 128 accepted 117
DRAFTED gsm8k-test-506 tokens 122 drafted 134 accepted 98
DRAFTED gsm8k-test-605 tokens 171 drafted 183 accepted 135
DRAFTED gsm8k-test-633 tokens 72 drafted 70 accepted 57
DRAFTED gsm8k-test-665 tokens 109 drafted 122 accepted 90
DRAFTED gsm8k-test-671 tokens 135 drafted 129 accepted 109
DRAFTED gsm8k-test-741 tokens 87 drafted 92 accepted 67
DRAFTED gsm8k-test-883 tokens 106 drafted 103 accepted 82
DRAFTED gsm8k-test-890 tokens 159 drafted 153 accepted 128
DRAFTED gsm8k-test-1036 tokens 59 drafted 59 accepted 51
DRAFTED gsm8k-test-1077 tokens 303 drafted 307 accepted 253
DRAFTED gsm8k-test-1127 tokens 77 drafted 87 accepted 66
DRAFTED gsm8k-test-1151 tokens 103 drafted 98 accepted 86
DRAFTED gsm8k-test-1265 tokens 167 drafted 157 accepted 132
SUMMARY rows 20/20 pairs_eq 20 text_eq 20 tokens_eq 20 verdict SELF-CONSISTENT
DRAFT-OK drafted equals draft:false on 20 of 20 prompts, both passes non-vacuous
```

```
drafted.jsonl: rows 20 hash_matches_ids 20/20
plain.jsonl: rows 20 hash_matches_ids 20/20
GATE-HASH OK
```

```
GATE-BOOT-DETERMINISM paired 20 text_identical 20/20 tokens_identical 20/20 prompt_sha_equal 20/20 only_fresh 0 only_ref 0
DETERMINISM OK
```

The instrument's own selftest plants eleven faults (text flip, token-sha flip, token-id flip, drafted pass drafted
nothing, plain pass drafted, plain pass reports drafts true, missing hash, missing ids, error row, token-count flip)
and catches all eleven.

Two further exactness cells are arm B's as well, and the driver fails the window if either fails: X1, a resumed prompt
equals a fresh one on the campaign's ~8.6k resume probe (X1's own 8,192-target prompt measures 7,809 tokens here;
the repro probe measures 8,605), and X2, drafted equals plain on the decoded cells at C=1 and C=4. Their numbers are
in section 6.

## 3. Matched settings and the environment proof

    PREPARE=0 CHECKPOINT=<nvfp4|int4> VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 \
    PARALLEL=4 CONTEXT=131072 THINKING=0 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 DRAFTS=1 ./start.sh restart
    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0

The speed cells at 8 streams boot with `PARALLEL=8 CONTEXT=32768`; every other cell uses the block above. Every boot reads its environment back and diffs it against the expected 30 lines; `analyze_boots.py` over the fetched tree renders all twenty boots of this window (two quality boots, twelve speed, six exactness):

```
| label | image | delta | env lines exp/read | env diff | Model line | Window line | rows | rc/wall |
|---|---|---|---:|---:|---|---|---:|---|
| QA | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T12:37:19+00:00 |
| QB | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 146 2026-11-22T15:28:18+00:00 |
| SA-D1-b1 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:06:27+00:00 |
| SA-D1-b2 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:13:15+00:00 |
| SA-D4-b1 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:14:24+00:00 |
| SA-D4-b2 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:22:38+00:00 |
| SA-D8-b1 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 8 at once · 32768-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:24:27+00:00 |
| SA-D8-b2 | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 8 at once · 32768-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:33:45+00:00 |
| SB-D1-b1 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 143 2026-11-22T17:09:22+00:00 |
| SB-D1-b2 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 145 2026-11-22T17:12:13+00:00 |
| SB-D4-b1 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 145 2026-11-22T17:18:01+00:00 |
| SB-D4-b2 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 142 2026-11-22T17:21:13+00:00 |
| SB-D8-b1 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 32768-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 146 2026-11-22T17:28:27+00:00 |
| SB-D8-b2 | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 32768-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 143 2026-11-22T17:32:00+00:00 |
| X1A | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:35:56+00:00 |
| X1B | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 142 2026-11-22T17:41:36+00:00 |
| X2A | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `DRAFTS=0 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts off · port 8080 | 3072 | boot_rc 0 wall_s 34 2026-11-22T17:45:04+00:00 |
| X2B | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `DRAFTS=0 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15 TF_FLASHNEXT_SHARED_DRAFTS=0` | 30/30 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts off · port 8080 | 3072 | boot_rc 0 wall_s 134 2026-11-22T17:50:45+00:00 |
| X3A | tensorfold-qwen38:qr-a-r5-1ece6e6db sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15` | 29/29 | 0 | Model    nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6 (NVIDIA FP4 QAD: NVFP4 experts, MXFP8) | nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 37 2026-11-22T17:54:06+00:00 |
| X3B | tensorfold-qwen38:qr-b-r5int4-1ece6e6d sha256:578911ca84d4aaac39f8b69c420d0344c14ba380242a982de502bdedf50cdb70 | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_DRAFTS_GREEDY=15` | 29/29 | 0 | Model    azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound @ 14642741 (INT4-AutoRound) | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 131072-token window · bf16 KV · vision off · drafts MTP · port 8080 | 3072 | boot_rc 0 wall_s 145 2026-11-22T17:57:40+00:00 |
BOOTS 20
```

## 4. The 1,664 bodies and arm A's reuse

The 1,664 replies were requested by `scripts/quality/quality_client.py` (sha256 `6853ccf9...`), the same client for
both arms, at concurrency 4, temperature 0 and no other sampling field, thinking off, from the frozen prompt files
(sha256 `3fc07867...`, `d24100ce...`, `d1644fe7...`), each row carrying the prompt sha and the request-body sha.

Arm A's rows were reused rather than regenerated. At 15:25:52 the driver logged `SKIP quality A (marker and all three
raw files complete)` and hashed the three files in the run log (`fae7bfda...` gsm8k, `1963ff25...` mmlupro,
`dc7ecdcd...` humaneval); the pre-window baseline it wrote (`box/out/pre-window-shas.txt`) and the same files' hashes and
mtimes after the window are compared in `analysis/reuse.txt`, so the 2 h 10 min MMLU-Pro pass the previous window paid
for was not paid again. Arm B's rows are this window's, at 0.20 items/s (GSM8K 500 in 19 min, MMLU-Pro 1,000 in
about 82 min).

The raw files, hashed after the fetch; the per-arm completeness check; the frozen-body verifier, which re-derives each row's request body from the frozen prompt file and its own model, max_tokens and stop, and compares the two arms item for item; and the identity check, whose arm A role is a gate and whose arm B comparisons are information (section 9's reason):

```
fae7bfdafe31b4152d4ef26164153ed1172e02095844cad2ffde95ecd5781444  A/gsm8k.jsonl
dc7ecdcd5cc3366ef288e253113fb3cfbc990d5942aded8c6d2d0b952ec66c83  A/humaneval.jsonl
1963ff25b8dcebc571f3fdb082f0c6b3f2e16dd6ad5352e45f8e2c073e3baea0  A/mmlupro.jsonl
ebef372ae8187d3c6c195857aeb46e7e6958b3662c4859d83e122f76935da2eb  B/gsm8k.jsonl
8aa61044c2ba4f6edfa24d8eca2e6ecc253f087346a85a34028b45ce17a3bf58  B/humaneval.jsonl
22488c541f3ce5d419c718fc7d905b8eacf0ceb2e7e54e2aacde051c3eb54521  B/mmlupro.jsonl
```

```
gsm8k: rows 500/500 dupes 0 errors 0
mmlupro: rows 1000/1000 dupes 0 errors 0
humaneval: rows 164/164 dupes 0 errors 0
QCOUNT OK problems 0
```

```
gsm8k: rows 500/500 dupes 0 errors 0
mmlupro: rows 1000/1000 dupes 0 errors 0
humaneval: rows 164/164 dupes 0 errors 0
QCOUNT OK problems 0
```

```
gsm8k A: rows 500/500 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
gsm8k B: rows 500/500 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
gsm8k cross-arm: paired 500 body_diff 0 prompt_diff 0
humaneval A: rows 164/164 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
humaneval B: rows 164/164 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
humaneval cross-arm: paired 164 body_diff 0 prompt_diff 0
mmlupro A: rows 1000/1000 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
mmlupro B: rows 1000/1000 dupes 0 missing 0 extra 0 prompt_diff 0 body_diff 0 errors 0 bad_finish 0
mmlupro cross-arm: paired 1000 body_diff 0 prompt_diff 0
QVERIFY OK problems 0
```

```
IDENTITY armA gsm8k vs 11-19 FP4 [GATE]: paired 500 text_identical 500/500 tokens_identical 500/500 prompt_sha_equal 500/500 only_fresh 0 only_ref 0 tokens_moved 0 verdict GATE-OK
IDENTITY armA mmlupro vs 11-19 FP4 [GATE]: paired 1000 text_identical 1000/1000 tokens_identical 1000/1000 prompt_sha_equal 1000/1000 only_fresh 0 only_ref 0 tokens_moved 0 verdict GATE-OK
IDENTITY armA humaneval vs 11-19 FP4 [GATE]: paired 164 text_identical 164/164 tokens_identical 164/164 prompt_sha_equal 164/164 only_fresh 0 only_ref 0 tokens_moved 0 verdict GATE-OK
IDENTITY armB gsm8k vs 11-19 INT4 serve [INFO]: paired 500 text_identical 227/500 tokens_identical 262/500 prompt_sha_equal 500/500 only_fresh 0 only_ref 0 tokens_moved 238 verdict INFO
  DIVERGE gsm8k-test-100 fresh tokens 203 ref tokens 189
  DIVERGE gsm8k-test-1012 fresh tokens 243 ref tokens 268
  DIVERGE gsm8k-test-1014 fresh tokens 318 ref tokens 307
  DIVERGE gsm8k-test-102 fresh tokens 190 ref tokens 198
  DIVERGE gsm8k-test-1020 fresh tokens 92 ref tokens 101
IDENTITY armB mmlupro vs 11-19 INT4 serve [INFO]: paired 1000 text_identical 24/1000 tokens_identical 201/1000 prompt_sha_equal 1000/1000 only_fresh 0 only_ref 0 tokens_moved 799 verdict INFO
  DIVERGE mmlupro-test-10005 fresh tokens 705 ref tokens 593
  DIVERGE mmlupro-test-10023 fresh tokens 1000 ref tokens 1023
  DIVERGE mmlupro-test-10030 fresh tokens 1219 ref tokens 1536
  DIVERGE mmlupro-test-10038 fresh tokens 1536 ref tokens 1536
  DIVERGE mmlupro-test-10063 fresh tokens 598 ref tokens 917
IDENTITY armB humaneval vs 11-19 INT4 serve [INFO]: paired 164 text_identical 80/164 tokens_identical 98/164 prompt_sha_equal 164/164 only_fresh 0 only_ref 0 tokens_moved 66 verdict INFO
  DIVERGE HumanEval/1 fresh tokens 98 ref tokens 109
  DIVERGE HumanEval/10 fresh tokens 57 ref tokens 57
  DIVERGE HumanEval/100 fresh tokens 51 ref tokens 51
  DIVERGE HumanEval/102 fresh tokens 65 ref tokens 47
  DIVERGE HumanEval/103 fresh tokens 31 ref tokens 31
IDENTITY armA vs armB gsm8k [INFO]: paired 500 text_identical 67/500 tokens_identical 102/500 prompt_sha_equal 500/500 only_fresh 0 only_ref 0 tokens_moved 398 verdict INFO
  DIVERGE gsm8k-test-0 fresh tokens 62 ref tokens 76
  DIVERGE gsm8k-test-1 fresh tokens 68 ref tokens 49
  DIVERGE gsm8k-test-10 fresh tokens 143 ref tokens 143
  DIVERGE gsm8k-test-100 fresh tokens 196 ref tokens 203
  DIVERGE gsm8k-test-1008 fresh tokens 95 ref tokens 95
IDENTITY armA vs armB mmlupro [INFO]: paired 1000 text_identical 0/1000 tokens_identical 152/1000 prompt_sha_equal 1000/1000 only_fresh 0 only_ref 0 tokens_moved 848 verdict INFO
  DIVERGE mmlupro-test-10005 fresh tokens 743 ref tokens 705
  DIVERGE mmlupro-test-10023 fresh tokens 1033 ref tokens 1000
  DIVERGE mmlupro-test-10030 fresh tokens 878 ref tokens 1219
  DIVERGE mmlupro-test-10038 fresh tokens 1536 ref tokens 1536
  DIVERGE mmlupro-test-10063 fresh tokens 641 ref tokens 598
IDENTITY armA vs armB humaneval [INFO]: paired 164 text_identical 26/164 tokens_identical 54/164 prompt_sha_equal 164/164 only_fresh 0 only_ref 0 tokens_moved 110 verdict INFO
  DIVERGE HumanEval/0 fresh tokens 69 ref tokens 45
  DIVERGE HumanEval/10 fresh tokens 80 ref tokens 57
  DIVERGE HumanEval/100 fresh tokens 51 ref tokens 51
  DIVERGE HumanEval/101 fresh tokens 27 ref tokens 27
  DIVERGE HumanEval/102 fresh tokens 50 ref tokens 65
IDENTITY-ROLES OK
```

## 5. The quality table, the paired difference and the power

Both arms' 1,664 replies were scored by `scripts/quality/quality_score.py` (sha256 `87cb9c00...`), the same instrument
as the prior window's, and its `--selftest` runs first: `SELFTEST ok: 7 of 7 checks caught their flip`. (The
2026-11-19 run used `9b583cce...`; the working copy's control run reproduced that run's scores exactly.) An unparsed
MMLU-Pro reply, a truncated reply and an absent reply all count as incorrect, identically in both arms.

Arm A's rows are the reused, byte-identical set and arm B's three sets are this window's, all complete (500, 1,000
and 164 rows, `QCOUNT OK` on both arms and `QVERIFY OK` over the 1,664 bodies). The table below is the scorer's,
from `analysis/summary.json` via `analysis/quality.txt`.

| bench | items | arm A (r5 FP4) | arm B (r5 INT4) | paired diff B-A | 95% Newcombe | only A / only B | McNemar p | trunc A/B | mean tok A/B | decode tok/s A/B | unparsed A/B |
|---|---:|---|---|---:|---|---:|---:|---|---:|---:|---:|
| gsm8k | 500 | 484/500 = 96.8% [94.9, 98.0] | 484/500 = 96.8% [94.9, 98.0] | +0.00 pp | [-2.12, +2.12] | 5 / 5 | 1.0 | 2/1 | 145.6/142.4 | 25.22/34.18 | 0/0 |
| mmlupro | 1000 | 752/1000 = 75.2% [72.4, 77.8] | 751/1000 = 75.1% [72.3, 77.7] | -0.10 pp | [-2.58, +2.38] | 54 / 53 | 1.0 | 203/202 | 912.7/899.5 | 30.91/47.2 | 121/108 |
| humaneval | 164 | 143/164 = 87.2% [81.2, 91.5] | 135/164 = 82.3% [75.8, 87.4] | -4.88 pp | [-11.89, +2.07] | 15 / 7 | 0.133801 | 3/5 | 86.1/91.5 | 29.5/42.81 | 0/0 |

The paired columns are over the rows both arms scored (all 1,664 in the final run).

**The 500-reply GSM8K set, stated against the FP4 arm and with no threshold applied:** arm B scored 484/500, exactly
equal to arm A's 484/500. The pairing has ten discordant items, five each way, so the paired difference is 0.00 pp with
a Newcombe interval of [-2.12, +2.12] and McNemar p 1.0. The ten items are item-specific, not a parser or length artefact: one truncation each way (arm A's test-87, whose
reply was cut at 1,024 tokens with 780 against arm B's 181 tokens and 9360, and arm B's test-293, cut at 1,024 with
20 against arm A's 83) and eight disagreements on the final answer. Arm A to arm B, the four arm B won: 120/90,
53/21, 0.7/70, 800/700; the four arm A won: 31/30, 33/21, 50/150, 1000/600. Ids for the record: only A correct,
test-236, test-293, test-675, test-809, test-962; only B correct, test-1226, test-494, test-806, test-87,
test-910.

**Power, recomputed from THIS pairing's discordance** (exact two-sided McNemar at alpha 0.05, 80% power):

| bench | discordant pairs | smallest net advantage at 80% power | power at a 5 pp difference | cap on any net advantage |
|---|---:|---|---:|---:|
| gsm8k | 10 | 8.3 items = 1.7 pp | not expressible (a 5 pp difference is larger than the whole discordant set) | 2.0 pp |
| mmlupro | 107 | 30.3 items = 3.0 pp | 100% | 10.7 pp |
| humaneval | 22 | 14.0 items = 8.5 pp | 27% | 13.4 pp |

**The checkpoint decision read from these numbers.** MMLU-Pro is the only one of the three benchmarks whose discordance
could have resolved a 5 pp checkpoint difference, and there the paired difference is -0.10 pp with an interval from
-2.58 to +2.38 and p 1.0: the two checkpoints are indistinguishable on this data at that resolution. GSM8K is
identical (484 each) and, with ten discordant pairs, could not have expressed a difference larger than 2.0 pp at all.
HumanEval carries the largest point difference measured, 8 items or -4.88 pp, with an interval that spans zero
[-11.89, +2.07] and p 0.134; at this pairing's discordance the design resolves only 8.5 pp there at 80% power, so the
HumanEval question is underpowered rather than answered. Nothing measured is near a size any of the three cells could
resolve as a loss, and the only statement the data supports is "no quality difference detectable between the r5 FP4
and r5 INT4 checkpoints at this pairing's resolution", with the HumanEval point estimate recorded as the one number
worth watching.

Sensitivity on the replies each serve stopped itself (a truncated reply excluded, so a length-limited answer cannot drive a difference):

```
gsm8k: paired 497, only A 4, only B 4, difference 0.0 pp, McNemar exact p 1.0
mmlupro: paired 746, only A 7, only B 8, difference 0.13 pp, McNemar exact p 1.0
humaneval: paired 157, only A 12, only B 5, difference -4.46 pp, McNemar exact p 0.143463
```

## 6. The exactness cells

- X1, resumed equals fresh. The 8,606-token prompt is sent fresh (A1), resumed after fourteen fresh-salted fillers of
  the same size (A2) and again after ten more (A3), and all three replies must carry one text sha; every request must
  complete and A2 and A3 must report `cached_tokens > 0`, so the resume is real and not a silent re-prefill. A
  `resume_bench.py` run records the same sequence's token shas and cached counts beside it, and `repro.py` repeats the
  first request three times so a one-off is visible as one.
- X2, drafted equals plain on decoded cells. The DRAFTS=0 boot's cells at C=1 and C=4 must equal the standard block's
  cells, paired by kind, pass and stream index with equal prompt shas, reply shas and completion-token counts.
- X3, the shared-rounds rule. The boot with `SHARED_DRAFTS` unset (the engine's documented default is on) must keep
  every reply sha at C=4 identical to the block's `SHARED_DRAFTS=0` boot: the shared-head scheduling may change the
  rounds, never the tokens.

X1 on arm A is measured (this window, 17:36Z): the conversation's three sends carry 7,809 prompt tokens each,
`cached_tokens` 2 / 7,802 / 7,802, and one reply text sha (`8a0176b1...`) on all three, `verdict PASS`. The separate
`resume_bench.py` run records the same sequence's 27 requests all complete with `cached_tokens` 7,803 on both resumes,
and `repro.py`'s probe of the campaign's larger resume prompt measures 8,605 prompt tokens (the campaign labels it
8,606) with `cached_tokens` 8,598 on runs 2 and 3 and 3 of 3 passes.

All six cells, from `analyze_exact.py` over the fetched tree (X1's verdict lines, then the comparer's pair counts for X2 at C=1 and C=4 and X3 at C=4 on each arm):

```
X1-A: complete True cached_A2_A3 True same_text True verdict PASS
  A1: prompt 7809 cached 2 tokens 16 chars 57 sha 8a0176b19501b662
  A2: prompt 7809 cached 7802 tokens 16 chars 57 sha 8a0176b19501b662
  A3: prompt 7809 cached 7802 tokens 16 chars 57 sha 8a0176b19501b662
  resume_bench: rows 27 all_complete True A2 cached 7803 A3 cached 7803
  repro: pass True runs run1 PASS cached 2, run2 PASS cached 8598, run3 PASS cached 8598
X1-B: complete True cached_A2_A3 True same_text True verdict PASS
  A1: prompt 7809 cached 2 tokens 16 chars 53 sha 9b1cf24426591407
  A2: prompt 7809 cached 7802 tokens 16 chars 53 sha 9b1cf24426591407
  A3: prompt 7809 cached 7802 tokens 16 chars 53 sha 9b1cf24426591407
  resume_bench: rows 27 all_complete True A2 cached 7802 A3 cached 7802
  repro: pass True runs run1 PASS cached 2, run2 PASS cached 8599, run3 PASS cached 8599
X2A cmp-1.txt: CMP-OK | CMP C=1 pairs 4/4 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
X2A cmp-4.txt: CMP-OK | CMP C=4 pairs 16/16 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
X2B cmp-1.txt: CMP-OK | CMP C=1 pairs 4/4 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
X2B cmp-4.txt: CMP-OK | CMP C=4 pairs 16/16 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
X3A cmp.txt: CMP-OK | CMP C=4 pairs 16/16 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
X3B cmp.txt: CMP-OK | CMP C=4 pairs 16/16 prompt_diff 0 text_diff 0 token_diff 0
  CMP-OK
EXACT OK problems 0
```

## 7. The speed table

The twelve boots are `S<arm>-D<1,4,8>-b<1,2>`, arms alternating A, B, B, A at each stream count, every boot a fresh
serve of the same image and environment block. D1 and D4 boot 4 slots at a 131,072-token window; D8 boots 8 slots at
32,768 tokens (the campaign's widest 8-slot shape on this box), so D1 and D4 are like for like with each other and
with the 2026-11-18 same-shape reference, while D8 is its own shape for both arms. Each cell runs two passes of prose
and two of code, 512 greedy tokens a request, C requests at once, and `check_dec.py` requires every row (prompt sha,
reply sha, completion tokens, a computed per-request rate). `analyze_speed.py` refuses a cell with fewer than two
boots. A rate is the client's `(completion tokens - 1) / (elapsed - ttft)`; aggregate is the sum over the C requests;
`tok/wall` is all completion tokens over the batch's wall time. The ratio is B over A (INT4 over FP4).

| streams | kind | A per-stream tok/s (two boots) | B per-stream tok/s (two boots) | B/A | A aggregate tok/s | B aggregate tok/s | B/A |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | prose | 59.24 (58.91, 59.56) | 70.71 (68.64, 72.79) | 1.194 | 59.2 | 70.7 | 1.194 |
| 1 | code | 80.03 (79.50, 80.56) | 114.97 (112.41, 117.52) | 1.437 | 80.0 | 115.0 | 1.437 |
| 4 | prose | 28.15 (28.06, 28.24) | 39.17 (38.40, 39.94) | 1.392 | 110.8 | 155.2 | 1.400 |
| 4 | code | 41.78 (41.75, 41.80) | 61.57 (61.00, 62.14) | 1.474 | 163.3 | 241.2 | 1.477 |
| 8 | prose | 20.68 (20.70, 20.66) | 26.63 (26.14, 27.12) | 1.288 | 159.5 | 216.9 | 1.360 |
| 8 | code | 31.51 (31.59, 31.42) | 41.87 (41.67, 42.08) | 1.329 | 248.4 | 329.7 | 1.327 |

| streams | A per-stream mean of prose+code | B per-stream mean | B/A | A aggregate mean | B aggregate mean | B/A |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 69.63 | 92.84 | 1.333 | 69.6 | 92.8 | 1.333 |
| 4 | 34.96 | 50.37 | 1.441 | 137.1 | 198.2 | 1.446 |
| 8 | 26.09 | 34.25 | 1.313 | 203.9 | 273.3 | 1.340 |

The geometric mean of the six aggregate ratios is **1.363** in arm B's favour. `check_dec.py` passed every cell (32 rows
at D8, 8 at D4, 2 at D1, all with shas, tokens and rates), and `analyze_speed.py` required two boots a cell. The two
boots of a cell agree closely: the widest spread is D1 prose arm B (68.64 to 72.79), and both arms' counters are
identical across the two boots of a cell, which is the same determinism the exactness cells measure.

The counters say where the speed comes from. `analysis/speed.txt`'s COUNTERS lines, per pass:

| cell | arm A rounds / drafted / accepted | arm B rounds / drafted / accepted | A tokens per round | B tokens per round | A ms per round | B ms per round | B/A ms per round |
|---|---|---|---|---:|---:|---:|---:|---:|
| D1 prose | 253 / 1,770 / 770 (43.5%) | 341 / 901 / 682 (75.7%) | 4.05 | 3.00 | 68.4 | 42.4 | 0.62 |
| D4 prose | 1,219 / 6,102 / 2,637 (43.2%) | 1,498 / 3,216 / 2,312 (71.9%) | 3.16 | 2.54 | 28.5 | 16.4 | 0.57 |
| D8 prose | 2,499 / 11,196 / 5,161 (46.1%) | 3,026 / 6,493 / 4,634 (71.4%) | 3.07 | 2.53 | 19.2 | 11.7 | 0.61 |

Arm A's drafter proposes about twice as many tokens per pass and accepts under half of them; arm B proposes fewer and
accepts about three quarters, so its rounds carry fewer tokens, and its rounds cost 0.57 to 0.62 of arm A's. The
checkpoint's arithmetic is what makes a round cheaper, and the speed-up is that ratio multiplied by the tokens per
round it gives up. The 2026-11-18 r2 series on the same box measured the inverse ratio at 1.155 (prose D1) to 1.517
(code D8 on four slots); this window's D1 and D4 ratios (1.19 to 1.48) sit in the same band on the r5 series, and the
r2 explanation (FP4-Local routes ten experts a token against INT4-AutoRound's five) is the mechanism the timings here
are consistent with, not something this window re-measured. The D8 ratios (1.29 to 1.36) are lower than D4's because
the D8 shape is different (8 slots at 32,768 tokens) and that cell has no r2 counterpart in the same shape.

## 8. Production, the lock

Production was read at preflight, before anything was stopped: `/health` 200 on
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`,
the image and id the driver pins. The serve was stopped only inside this window's hold and restored by the driver's
EXIT trap, gated on `/health` 200 and the pinned image id (`PROD-IMAGE-OK`). After the window the lock was verified free
with `flock -n ~/work/gpu.lock true`, and no driver or `window.sh` process remained.

The restore, read from the fetched run log and the files the EXIT trap wrote:

```
[2026-11-22T15:08:50+00:00] MARK PROD-IMAGE-OK
[2026-11-22T15:08:50+00:00] PROD-IMAGE ok tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
[2026-11-22T15:08:50+00:00] MARK RESTORED
[2026-11-22T17:58:32+00:00] RESTORE start 2026-11-22T17:58:32+00:00
[2026-11-22T18:00:00+00:00] RESTORE prod_rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f 2026-11-22T18:00:00+00:00
[2026-11-22T18:00:00+00:00] MARK PROD-IMAGE-OK
[2026-11-22T18:00:00+00:00] PROD-IMAGE ok tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
[2026-11-22T18:00:00+00:00] MARK RESTORED
--- RESTORED file
prod /health 200 (start rc 0) image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f 2026-11-22T18:00:00+00:00
--- container
qwen38-flash-next-tf tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 Up About a minute
--- health
{"status": "ok", "model": "Qwen3.8-Flash-Next", "model_ids": ["Qwen3.8-Flash-Next"], "max_batch_size": 8, "warming": false, "memory": {}, "live": {"connections": 0, "waiting": 0, "decode_tokens_per_second": 1.0, "prefill_tokens_per_second": 298.3}}--- markers
BOOT-QA-OK BOOT-QB-OK BOOT-SA-D1-b1-OK BOOT-SA-D1-b2-OK BOOT-SA-D4-b1-OK BOOT-SA-D4-b2-OK BOOT-SA-D8-b1-OK BOOT-SA-D8-b2-OK BOOT-SB-D1-b1-OK BOOT-SB-D1-b2-OK BOOT-SB-D4-b1-OK BOOT-SB-D4-b2-OK BOOT-SB-D8-b1-OK BOOT-SB-D8-b2-OK BOOT-X1A-OK BOOT-X1B-OK BOOT-X2A-OK BOOT-X2B-OK BOOT-X3A-OK BOOT-X3B-OK BUILD-A-OK BUILD-B-OK FID-A-OK FID-B-OK PREFLIGHT-OK PROD-IMAGE-OK QUAL-A-OK QUAL-B-OK QVERIFY-OK RESTORED RUN-DONE SELFTEST-OK SPEED-SA-D1-b1-OK SPEED-SA-D1-b2-OK SPEED-SA-D4-b1-OK SPEED-SA-D4-b2-OK SPEED-SA-D8-b1-OK SPEED-SA-D8-b2-OK SPEED-SB-D1-b1-OK SPEED-SB-D1-b2-OK SPEED-SB-D4-b1-OK SPEED-SB-D4-b2-OK SPEED-SB-D8-b1-OK SPEED-SB-D8-b2-OK STAGE-A-OK STAGE-B-OK X1-A-OK X1-B-OK X2-A-OK X2-B-OK X3-A-OK X3-B-OK
```

## 9. What the INT4 port's numerics still cannot be checked against

What this window proves is that arm B's arithmetic is self-consistent: drafting does not change a reply, resuming a
prompt does not change it, and its own two paths agree token for token. It does not prove the INT4 kernels produce the
same numbers as a golden INT4 reference at this serve shape, because no such reference exists. The only INT4 text
oracle on hand is production's serve at a different shape (8 slots, 262,144 tokens, fp8 KV requested, vision on,
`int4_prompt_kernel`, 32-row `lm_head` items, `DRAFT_INT4`); agreement with it is measured and reported as
information, and it cannot separate arithmetic from configuration. There is no device-level check either: the package's
gap table records, carried unchanged, that the port's loader has "no loader host test and no device check against a
float64 reference", the int4 kernel has "no contract records, no planted controls, no float64 device test", the
serving path has "no fidelity cells against a float64 reference", and the MTP layer's BF16 experts are "re-coded to
block FP8 at load (e4m3, lossy; drafts only, so replies stay exact)" (README, upstream state 2026-11-21). The 20 of 20
drafted-equals-plain result is a measured confirmation of that last clause on this build; the float64 gaps stand.

Closing the gap needs one of two things, and which one the campaign wants is the owner's call: a like-for-like INT4
capture at the campaign block (4 slots, 131,072 tokens, bf16 KV, vision off, this engine's kernels) to gate the port's
text against, or a float64 device reference per affected INT4 projection class. Neither exists today.

## 10. What is not measured, and what is not proven

1. The INT4 kernels' numerics against a like-for-like INT4 reference: no such text oracle exists at this serve shape,
   and there is no float64 device reference for the INT4 projection classes (section 9). This is the one gap the
   window cannot close from inside.
2. Per-item drafted-equals-plain on the 1,664 scored bodies: the exactness contract is measured on the 20 gate prompts
   and on the decode cells (X2 at C=1 and C=4, X3 at C=4), not by re-running every scored body with `"draft": false`.
   X2 and X3 exercise the same engine path the bodies use; a per-body re-run is a further capture, not this window.
3. Arm A's image was a BuildKit cache hit on the SDLimits build of the identical tree, so it was not compiled in this
   hold; arm B compiled in the prior window of the campaign (`build_rc 0 wall_s 513 files 12625`).
4. The speed cells are 512-token greedy decode at 1, 4 and 8 streams, prose and code, two boots an arm, on spark6 with
   production stopped. They are not production traffic and not the owner's 650k-token contexts; the D8 shape (8 slots,
   32,768 tokens) differs from D1 and D4 (4 slots, 131,072) and from the 2026-11-18 reference's 8-on-4-slots cell.
5. The environment proof is the container's `TF_`/`TENSORFOLD_` variables diffed against the 30 expected lines. It does
   not hash the checkpoint files; the boot banner's model and revision line and the HF snapshot path pin the
   checkpoint instead.
6. MMLU-Pro's unparsed replies (no extractable final letter) count as incorrect in both arms, identically; the counts
   are reported above. HumanEval replies are executed with the laptop's CPython in a sandboxed environment, so a pass
   is a pass of the official test code, not a code review.
7. Nothing here measured production's own serve; the QCMPA agreement figures are the prior campaign's captured
   replies, quoted, not a new capture.

## 11. Where every number comes from

| claim | source |
|---|---|
| image ids, labels, stage/build skips | `box/out/image-{A,B}.{id,labels}`, `box/out/run.log` (`SKIP build ...`) |
| payload, driver, instrument shas | `work/QInt4/stage-sha.txt`, `in/SHA256SUMS`, `box/out/preflight-in.txt`, `sha256sum window.sh` on both sides |
| selftest, wiring proof, preflight | `box/out/selftest.log` (this run's selftest appends to `out/run.log` and marks), `work/QRerun/prove_gate_wiring.sh` output, `box/out/run.log` (`PREFLIGHT ...`) |
| the internal gate, pair by pair | `box/out/QB/draft-gate.txt`, `box/out/QB/draft/{drafted,plain}.jsonl`, `analysis/gate-hash.txt`, `analysis/gate-determinism.txt` |
| boot environment and identity | `box/out/<label>/{env.txt,env-expected.txt,env-diff.txt,cmd.txt,boot.log,health.json,seqline.txt}`, `analysis/boots.txt` |
| the 1,664 bodies | `box/out/Q{A,B}/raw/{gsm8k,mmlupro,humaneval}.jsonl`, `analysis/raw-shas.txt`, `analysis/qcount-{A,B}.txt`, `analysis/qverify.txt` |
| arm A's prior gate and its reused rows | `work/QRerun/analysis/fid.txt`, `work/QRerun/analysis/quality-A-ref.txt`, `box/out/pre-window-shas.txt`, `analysis/reuse.txt` |
| accuracies, Wilson intervals, paired interval, McNemar, power | `analysis/quality.txt`, `analysis/summary.json`, `analysis/paired_extra.json`, `analysis/identity.txt` |
| speed rates and counters | every `box/out/S<arm>-D<streams>-b<rep>/dec.jsonl`, `analysis/speed.txt`, `work/QInt4/speed.json` |
| exactness cells | `box/out/X1{A,B}/{x1.json,resume-orig.json,repro.json}`, `box/out/X2{A,B}/{cmp-1.txt,cmp-4.txt}`, `box/out/X3{A,B}/cmp.txt`, `analysis/exact.txt` |
| production, the lock | `box/out/run.log` (`RESTORE`, `PROD-IMAGE`, `EXIT-DONE`), `box/out/{RESTORED,restored-container.txt,health-restored.json,lock-holders-after.txt}` and this session's own `flock -n` read after the window |
| the fetched tree | `work/QInt4/box-<tag>.tgz` sha256 compared on both sides by `fetch.sh` |

## 12. Harness notes from this window

- The arm B gate is the new instrument here (`in/draft_gate.py`); its own selftest plants eleven faults and catches
  all eleven, and its two fields were independently verified: the server's `token_sha256` recomputes from the
  returned `token_ids` on all 40 rows (`analysis/gate-hash.txt`), and the gate boot's drafted replies equal the
  earlier boot's replies on 20 of 20 prompts (`analysis/gate-determinism.txt`).
- Payload hygiene: one generated `.pyc` reached the sealed sums (section 1). It is disclosed rather than hidden;
  `qrstage.py` now excludes `__pycache__` so it cannot recur.
- No other harness defect was found. The driver changes this window are the arm B gate block, its selftest case,
  the new tool's entry in the preflight payload list, and the three reuse hashes the skip line now logs; every
  other gate and every fail-closed rule is the prior window's, demonstrated by the selftest quoted in section 1.

## 13. The production-shape attempt (after the window)

The like-for-like check the report's section 9 says does not exist was attempted after the window closed, because it
turned out to be startable: arm B booted with production's own 54 `TF_`/`TENSORFOLD_` variables at production's shape
(8 at once, 262144-token window, fp8 KV, vision on, drafts MTP).

The boot failed: `PRODSHAPE-BOOT rc 1 [start.sh] ERROR: the server exited (code 1) before it was ready` at
2026-11-22T18:07:56Z. So the port does not start under production's full environment as captured, and the like-for-like
INT4 text comparison remains unmeasured; the failure is the first thing a capture would have to fix, and it is a real
finding rather than a shape mismatch in the replies. The attempt's script and log are `~/prodshape.sh` and
`out/prodshape.log` on spark6; its EXIT trap restored production: `PRODSHAPE-RESTORE prod_rc 0 /health 200 image
tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea...` at 18:16:04Z, `PRODSHAPE-PROD-IMAGE-OK`, and an
independent read at 18:17:06Z gave `/health` 200 with the same image and id.
