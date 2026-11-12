# recipe-patches - the two levers measured on upstream 1.2.4, as recipe patches

> RETIRED REFERENCE: the Gitea repository `ots/tensorfold-levers124` named in this file no longer exists. Every ref it held is in
> `archive/tensorfold-levers124/levers124.bundle` (`REFS.txt` lists them; `README.md` there says how to restore one). The
> production engine source is the branch `production` of this repository.

Exported from the verified branches on Gitea `ots/tensorfold-levers124` (the branches are the source of truth;
regenerate with `git diff <base>.. <head>` rather than editing these):

- `0064-copy-resync-shared-ramp.patch` - branch `port-copy-windows-ab4b2f05` @ `0d951b3bd`, diffed against
  upstream `ab4b2f05` (v1.2.4's release commit, 2026-11-07). Adds `TENSORFOLD_COPY_RESYNC`,
  `_PROMPT_ONLY`, `_SHARED`, `_MISS`, `_RAMP` (all off/unset by default). Measured: one-word rewrite
  230.5 -> 300.2 tok/s (+30.2%), two concurrent edits 142.1/142.3 -> 201.5/212.6 (+41.7/+49.3%),
  edit-beside-prose 148.9/47.8 -> 234.8/50.2, verbatim copy flat; plain decode flat within 0.9% on the
  maintainer's own tools. Receipt: `docs/receipts/flashnext-copy-resync/` on that branch.
- `0065-copy-windows-48-rows.patch` - branch `port-64rows-v2` @ `7bf66d350`, diffed against upstream
  `267c5af6a`. Raises the copy window to 64 with a boot-time self-check that serves the largest row-exact
  prefix and falls back to 32 rows; on the NVFP4 checkpoint the boundary measured at 48 rows (width 49 the
  first differing: the pending-row log, `batch.late_rows = 48`). Verbatim copy 374.3 -> 473.7 tok/s (+26.6%),
  one-word rewrite 228.8 -> 256.7 (+12.2%); edits and plain decode flat; +0.05 GiB device a drafting stream.

Apply order: `0064` then `0065` - both verified to apply cleanly in that order on upstream `267c5af6a` and on
`ab4b2f05` (code paths only; the 0064 export also carries the ab4b2f05 receipt, which does not apply onto a
tree that already has it - use `--exclude=docs/*` there). Both are off-means-stock: unset settings leave
upstream's behaviour verbatim, and 0065's self-check floors the served width at upstream's 32 rows.
