| check | measure | main | branch |
|---|---|---|---|
| drafted == draft:false | bench_concurrent --serial, code+chat, greedy | 2/2 equal ([256] tok) | 2/2 equal ([256] tok) |
| drafted == draft:false | bench_concurrent --serial, code+chat, temperature 1.0 | 8/8 equal ([256] tok) | 8/8 equal ([256] tok) |
| drafted == draft:false | bench_concurrent --serial, six golden, greedy | 6/6 equal ([256] tok) | 6/6 equal ([256] tok) |
| drafted == draft:false | served_exactness drafts, cache on | 8/8 equal (token_ids); accepted 13-237 a reply | 8/8 equal (token_ids); accepted 13-237 a reply |
| drafted == draft:false | served_exactness drafts, cache off | 8/8 equal (token_ids); accepted 13-237 a reply | 8/8 equal (token_ids); accepted 13-237 a reply |
| resumed == fresh | served_exactness turns (on) against fresh (off) | 7/7 equal (token_ids) | 7/7 equal (token_ids) |
| concurrent == solo | bench_concurrent --alone, code+chat, 1/2/4, greedy | 42/42 equal, 0 failed | 42/42 equal, 0 failed |
| concurrent == solo | bench_concurrent --alone, code+chat, 1/2/4, temperature 1.0 | 42/42 equal, 0 failed | 42/42 equal, 0 failed |
| concurrent == solo | bench_concurrent --alone, six golden, 1/2/4/6, greedy | 13/13 equal, 0 failed | 13/13 equal, 0 failed |

Branch replies against main's (same request, same boot kind):
- conc: alone+serial token hashes 16/16 equal
- gold: alone+serial token hashes 6/6 equal
- d_on: plain token ids 8/8 equal
- d_off: plain token ids 8/8 equal
- turn first: token ids 7/7 equal
- turn resumed: token ids 7/7 equal

Receipt arms' bench_concurrent alone+serial token hashes (widest cell, first rep) against M1's:
- B1: 8/8 equal; alone {0.0: [42, 0, 0]}, serial {0.0: [2, 0, 0]}, failed 0
- B2: 8/8 equal; alone {0.0: [42, 0, 0]}, serial {0.0: [2, 0, 0]}, failed 0
- M2: 8/8 equal; alone {0.0: [42, 0, 0]}, serial {0.0: [2, 0, 0]}, failed 0
