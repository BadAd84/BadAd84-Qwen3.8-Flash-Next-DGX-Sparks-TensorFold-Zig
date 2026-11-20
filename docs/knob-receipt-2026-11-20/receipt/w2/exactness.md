# Exactness, window w2

| arm | cell | equal | total | basis |
| --- | --- | --- | --- | --- |
| C4096 | drafts | 8 | 8 | token_ids |
| C4096 | turns | 7 | 7 | resumed_from_cache |
| C4096 | drafts | 8 | 8 | token_ids |
| C4096 | fresh | 7 | 7 | token_ids |
| C4096b | drafts | 8 | 8 | token_ids |
| C4096b | turns | 7 | 7 | resumed_from_cache |
| C4096b | drafts | 8 | 8 | token_ids |
| C4096b | fresh | 7 | 7 | token_ids |
| C6144 | drafts | 8 | 8 | token_ids |
| C6144 | turns | 7 | 7 | resumed_from_cache |
| C6144 | drafts | 8 | 8 | token_ids |
| C6144 | fresh | 7 | 7 | token_ids |
| C6144b | drafts | 8 | 8 | token_ids |
| C6144b | turns | 7 | 7 | resumed_from_cache |
| C6144b | drafts | 8 | 8 | token_ids |
| C6144b | fresh | 7 | 7 | token_ids |
| DEVCK | drafts | 8 | 8 | token_ids |
| DEVCK | turns | 7 | 7 | resumed_from_cache |
| DEVCKb | drafts | 8 | 8 | token_ids |
| DEVCKb | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | fresh | 7 | 7 | token_ids |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | turns | 7 | 7 | resumed_from_cache |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | fresh | 7 | 7 | token_ids |
| PRICE | drafts | 8 | 8 | token_ids |
| PRICE | turns | 7 | 7 | resumed_from_cache |
| PRICEb | drafts | 8 | 8 | token_ids |
| PRICEb | turns | 7 | 7 | resumed_from_cache |
| RESERVE | drafts | 8 | 8 | token_ids |
| RESERVE | turns | 7 | 7 | resumed_from_cache |
| RESERVEb | drafts | 8 | 8 | token_ids |
| RESERVEb | turns | 7 | 7 | resumed_from_cache |
| S3072 | drafts | 8 | 8 | token_ids |
| S3072 | turns | 7 | 7 | resumed_from_cache |
| S3072 | drafts | 8 | 8 | token_ids |
| S3072 | fresh | 7 | 7 | token_ids |
| S3072b | drafts | 8 | 8 | token_ids |
| S3072b | turns | 7 | 7 | resumed_from_cache |
| S3072b | drafts | 8 | 8 | token_ids |
| S3072b | fresh | 7 | 7 | token_ids |

Concurrent equals solo (temperature 1 and 0, streams against the solo stream):

| arm | prompt | temp | streams | equal | total |
| --- | --- | --- | --- | --- | --- |
| C4096 | a/code | 1.0 | 2 | 2 | 2 |
| C4096 | a/code | 1.0 | 4 | 2 | 2 |
| C4096 | a/code | 1.0 | 6 | 2 | 2 |
| C4096 | a/chat | 1.0 | 2 | 2 | 2 |
| C4096 | a/chat | 1.0 | 4 | 2 | 2 |
| C4096 | a/chat | 1.0 | 6 | 2 | 2 |
| C4096 | a/code | 0.0 | 2 | 2 | 2 |
| C4096 | a/code | 0.0 | 4 | 2 | 2 |
| C4096 | a/code | 0.0 | 6 | 2 | 2 |
| C4096 | a/chat | 0.0 | 2 | 2 | 2 |
| C4096 | a/chat | 0.0 | 4 | 2 | 2 |
| C4096 | a/chat | 0.0 | 6 | 2 | 2 |
| C4096b | a/code | 1.0 | 2 | 2 | 2 |
| C4096b | a/code | 1.0 | 4 | 2 | 2 |
| C4096b | a/code | 1.0 | 6 | 2 | 2 |
| C4096b | a/chat | 1.0 | 2 | 2 | 2 |
| C4096b | a/chat | 1.0 | 4 | 2 | 2 |
| C4096b | a/chat | 1.0 | 6 | 2 | 2 |
| C4096b | a/code | 0.0 | 2 | 2 | 2 |
| C4096b | a/code | 0.0 | 4 | 2 | 2 |
| C4096b | a/code | 0.0 | 6 | 2 | 2 |
| C4096b | a/chat | 0.0 | 2 | 2 | 2 |
| C4096b | a/chat | 0.0 | 4 | 2 | 2 |
| C4096b | a/chat | 0.0 | 6 | 2 | 2 |
| C6144 | a/code | 1.0 | 2 | 2 | 2 |
| C6144 | a/code | 1.0 | 4 | 2 | 2 |
| C6144 | a/code | 1.0 | 6 | 2 | 2 |
| C6144 | a/chat | 1.0 | 2 | 2 | 2 |
| C6144 | a/chat | 1.0 | 4 | 2 | 2 |
| C6144 | a/chat | 1.0 | 6 | 2 | 2 |
| C6144 | a/code | 0.0 | 2 | 2 | 2 |
| C6144 | a/code | 0.0 | 4 | 2 | 2 |
| C6144 | a/code | 0.0 | 6 | 2 | 2 |
| C6144 | a/chat | 0.0 | 2 | 2 | 2 |
| C6144 | a/chat | 0.0 | 4 | 2 | 2 |
| C6144 | a/chat | 0.0 | 6 | 2 | 2 |
| C6144b | a/code | 1.0 | 2 | 2 | 2 |
| C6144b | a/code | 1.0 | 4 | 2 | 2 |
| C6144b | a/code | 1.0 | 6 | 2 | 2 |
| C6144b | a/chat | 1.0 | 2 | 2 | 2 |
| C6144b | a/chat | 1.0 | 4 | 2 | 2 |
| C6144b | a/chat | 1.0 | 6 | 2 | 2 |
| C6144b | a/code | 0.0 | 2 | 2 | 2 |
| C6144b | a/code | 0.0 | 4 | 2 | 2 |
| C6144b | a/code | 0.0 | 6 | 2 | 2 |
| C6144b | a/chat | 0.0 | 2 | 2 | 2 |
| C6144b | a/chat | 0.0 | 4 | 2 | 2 |
| C6144b | a/chat | 0.0 | 6 | 2 | 2 |
| DEVCK | a/code | 1.0 | 2 | 2 | 2 |
| DEVCK | a/code | 1.0 | 4 | 2 | 2 |
| DEVCK | a/code | 1.0 | 6 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 2 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 4 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 6 | 2 | 2 |
| DEVCK | a/code | 0.0 | 2 | 2 | 2 |
| DEVCK | a/code | 0.0 | 4 | 2 | 2 |
| DEVCK | a/code | 0.0 | 6 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 2 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 4 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 6 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 2 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 4 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 6 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 2 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 4 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 6 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 2 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 4 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 6 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 2 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 4 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 6 | 2 | 2 |
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
| PRICE | a/code | 1.0 | 2 | 2 | 2 |
| PRICE | a/code | 1.0 | 4 | 2 | 2 |
| PRICE | a/code | 1.0 | 6 | 2 | 2 |
| PRICE | a/chat | 1.0 | 2 | 2 | 2 |
| PRICE | a/chat | 1.0 | 4 | 2 | 2 |
| PRICE | a/chat | 1.0 | 6 | 2 | 2 |
| PRICE | a/code | 0.0 | 2 | 2 | 2 |
| PRICE | a/code | 0.0 | 4 | 2 | 2 |
| PRICE | a/code | 0.0 | 6 | 2 | 2 |
| PRICE | a/chat | 0.0 | 2 | 2 | 2 |
| PRICE | a/chat | 0.0 | 4 | 2 | 2 |
| PRICE | a/chat | 0.0 | 6 | 2 | 2 |
| PRICEb | a/code | 1.0 | 2 | 2 | 2 |
| PRICEb | a/code | 1.0 | 4 | 2 | 2 |
| PRICEb | a/code | 1.0 | 6 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 2 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 4 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 6 | 2 | 2 |
| PRICEb | a/code | 0.0 | 2 | 2 | 2 |
| PRICEb | a/code | 0.0 | 4 | 2 | 2 |
| PRICEb | a/code | 0.0 | 6 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 2 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 4 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 6 | 2 | 2 |
| RESERVE | a/code | 1.0 | 2 | 2 | 2 |
| RESERVE | a/code | 1.0 | 4 | 2 | 2 |
| RESERVE | a/code | 1.0 | 6 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 2 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 4 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 6 | 2 | 2 |
| RESERVE | a/code | 0.0 | 2 | 2 | 2 |
| RESERVE | a/code | 0.0 | 4 | 2 | 2 |
| RESERVE | a/code | 0.0 | 6 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 2 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 4 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 6 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 2 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 4 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 6 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 2 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 4 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 6 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 2 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 4 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 6 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 2 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 4 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 6 | 2 | 2 |
| S3072 | a/code | 1.0 | 2 | 2 | 2 |
| S3072 | a/code | 1.0 | 4 | 2 | 2 |
| S3072 | a/code | 1.0 | 6 | 2 | 2 |
| S3072 | a/chat | 1.0 | 2 | 2 | 2 |
| S3072 | a/chat | 1.0 | 4 | 2 | 2 |
| S3072 | a/chat | 1.0 | 6 | 2 | 2 |
| S3072 | a/code | 0.0 | 2 | 2 | 2 |
| S3072 | a/code | 0.0 | 4 | 2 | 2 |
| S3072 | a/code | 0.0 | 6 | 2 | 2 |
| S3072 | a/chat | 0.0 | 2 | 2 | 2 |
| S3072 | a/chat | 0.0 | 4 | 2 | 2 |
| S3072 | a/chat | 0.0 | 6 | 2 | 2 |
| S3072b | a/code | 1.0 | 2 | 2 | 2 |
| S3072b | a/code | 1.0 | 4 | 2 | 2 |
| S3072b | a/code | 1.0 | 6 | 2 | 2 |
| S3072b | a/chat | 1.0 | 2 | 2 | 2 |
| S3072b | a/chat | 1.0 | 4 | 2 | 2 |
| S3072b | a/chat | 1.0 | 6 | 2 | 2 |
| S3072b | a/code | 0.0 | 2 | 2 | 2 |
| S3072b | a/code | 0.0 | 4 | 2 | 2 |
| S3072b | a/code | 0.0 | 6 | 2 | 2 |
| S3072b | a/chat | 0.0 | 2 | 2 | 2 |
| S3072b | a/chat | 0.0 | 4 | 2 | 2 |
| S3072b | a/chat | 0.0 | 6 | 2 | 2 |
