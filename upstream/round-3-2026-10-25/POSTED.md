Round 3 replies, posted 2026-10-25 (owner-approved), restyled on paperclip

| PR | reply |
|---|---|
| #34 | close fine; INT4 +8-9% code at 1/2/4 clients; CHECKPOINT=int4 scope better than single-client |
| #36 | MTP_FP8 was INT4-only; rebase as CHECKPOINT=int4 strict setting |
| #42 | not needed on FP4 (NgramTable.nv has own threads + WARM_AHEAD); touch() row-width note flagged |
| #48 | fused tiles are mode 3 only; CHECKPOINT=int4; dispatch where l.mx8 false |
| #53 | thanks for landing 0021; fill-check + docs to follow |
