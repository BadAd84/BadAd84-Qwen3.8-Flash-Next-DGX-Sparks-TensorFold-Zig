# Exactness, window w1

| arm | cell | equal | total | basis |
| --- | --- | --- | --- | --- |
| C1536 | drafts | 8 | 8 | token_ids |
| C1536 | turns | 7 | 7 | resumed_from_cache |
| C1536 | drafts | 8 | 8 | token_ids |
| C1536 | fresh | 7 | 7 | token_ids |
| C1536b | drafts | 8 | 8 | token_ids |
| C1536b | turns | 7 | 7 | resumed_from_cache |
| C1536b | drafts | 8 | 8 | token_ids |
| C1536b | fresh | 7 | 7 | token_ids |
| F1 | drafts | 8 | 8 | token_ids |
| F1 | turns | 7 | 7 | resumed_from_cache |
| F1 | drafts | 8 | 8 | token_ids |
| F1 | fresh | 7 | 7 | token_ids |
| F1b | drafts | 8 | 8 | token_ids |
| F1b | turns | 7 | 7 | resumed_from_cache |
| F1b | drafts | 8 | 8 | token_ids |
| F1b | fresh | 7 | 7 | token_ids |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | fresh | 7 | 7 | token_ids |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | turns | 7 | 7 | resumed_from_cache |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | fresh | 7 | 7 | token_ids |

Concurrent equals solo (temperature 1 and 0, streams against the solo stream):

| arm | prompt | temp | streams | equal | total |
| --- | --- | --- | --- | --- | --- |
| C1536 | a/code | 1.0 | 2 | 2 | 2 |
| C1536 | a/code | 1.0 | 4 | 2 | 2 |
| C1536 | a/code | 1.0 | 6 | 2 | 2 |
| C1536 | a/chat | 1.0 | 2 | 2 | 2 |
| C1536 | a/chat | 1.0 | 4 | 2 | 2 |
| C1536 | a/chat | 1.0 | 6 | 2 | 2 |
| C1536 | a/code | 0.0 | 2 | 2 | 2 |
| C1536 | a/code | 0.0 | 4 | 2 | 2 |
| C1536 | a/code | 0.0 | 6 | 2 | 2 |
| C1536 | a/chat | 0.0 | 2 | 2 | 2 |
| C1536 | a/chat | 0.0 | 4 | 2 | 2 |
| C1536 | a/chat | 0.0 | 6 | 2 | 2 |
| C1536b | a/code | 1.0 | 2 | 2 | 2 |
| C1536b | a/code | 1.0 | 4 | 2 | 2 |
| C1536b | a/code | 1.0 | 6 | 2 | 2 |
| C1536b | a/chat | 1.0 | 2 | 2 | 2 |
| C1536b | a/chat | 1.0 | 4 | 2 | 2 |
| C1536b | a/chat | 1.0 | 6 | 2 | 2 |
| C1536b | a/code | 0.0 | 2 | 2 | 2 |
| C1536b | a/code | 0.0 | 4 | 2 | 2 |
| C1536b | a/code | 0.0 | 6 | 2 | 2 |
| C1536b | a/chat | 0.0 | 2 | 2 | 2 |
| C1536b | a/chat | 0.0 | 4 | 2 | 2 |
| C1536b | a/chat | 0.0 | 6 | 2 | 2 |
| F1 | a/code | 1.0 | 2 | 2 | 2 |
| F1 | a/code | 1.0 | 4 | 2 | 2 |
| F1 | a/code | 1.0 | 6 | 2 | 2 |
| F1 | a/chat | 1.0 | 2 | 2 | 2 |
| F1 | a/chat | 1.0 | 4 | 2 | 2 |
| F1 | a/chat | 1.0 | 6 | 2 | 2 |
| F1 | a/code | 0.0 | 2 | 2 | 2 |
| F1 | a/code | 0.0 | 4 | 2 | 2 |
| F1 | a/code | 0.0 | 6 | 2 | 2 |
| F1 | a/chat | 0.0 | 2 | 2 | 2 |
| F1 | a/chat | 0.0 | 4 | 2 | 2 |
| F1 | a/chat | 0.0 | 6 | 2 | 2 |
| F1b | a/code | 1.0 | 2 | 2 | 2 |
| F1b | a/code | 1.0 | 4 | 2 | 2 |
| F1b | a/code | 1.0 | 6 | 2 | 2 |
| F1b | a/chat | 1.0 | 2 | 2 | 2 |
| F1b | a/chat | 1.0 | 4 | 2 | 2 |
| F1b | a/chat | 1.0 | 6 | 2 | 2 |
| F1b | a/code | 0.0 | 2 | 2 | 2 |
| F1b | a/code | 0.0 | 4 | 2 | 2 |
| F1b | a/code | 0.0 | 6 | 2 | 2 |
| F1b | a/chat | 0.0 | 2 | 2 | 2 |
| F1b | a/chat | 0.0 | 4 | 2 | 2 |
| F1b | a/chat | 0.0 | 6 | 2 | 2 |
| M1 | a/code | 1.0 | 2 | 2 | 2 |
| M1 | a/code | 1.0 | 4 | 2 | 2 |
| M1 | a/code | 1.0 | 6 | 2 | 2 |
| M1 | a/chat | 1.0 | 2 | 2 | 2 |
| M1 | a/chat | 1.0 | 4 | 2 | 2 |
| M1 | a/chat | 1.0 | 6 | 2 | 2 |
| M1 | a/code | 0.0 | 2 | 2 | 2 |
| M1 | a/code | 0.0 | 4 | 2 | 2 |
| M1 | a/code | 0.0 | 6 | 2 | 2 |
| M1 | a/chat | 0.0 | 2 | 2 | 2 |
| M1 | a/chat | 0.0 | 4 | 2 | 2 |
| M1 | a/chat | 0.0 | 6 | 2 | 2 |
| M2 | a/code | 1.0 | 2 | 2 | 2 |
| M2 | a/code | 1.0 | 4 | 2 | 2 |
| M2 | a/code | 1.0 | 6 | 2 | 2 |
| M2 | a/chat | 1.0 | 2 | 2 | 2 |
| M2 | a/chat | 1.0 | 4 | 2 | 2 |
| M2 | a/chat | 1.0 | 6 | 2 | 2 |
| M2 | a/code | 0.0 | 2 | 2 | 2 |
| M2 | a/code | 0.0 | 4 | 2 | 2 |
| M2 | a/code | 0.0 | 6 | 2 | 2 |
| M2 | a/chat | 0.0 | 2 | 2 | 2 |
| M2 | a/chat | 0.0 | 4 | 2 | 2 |
| M2 | a/chat | 0.0 | 6 | 2 | 2 |
