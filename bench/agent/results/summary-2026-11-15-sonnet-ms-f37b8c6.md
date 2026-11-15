# Agent bench, 2026-11-15: Sonnet, Manuscript only, main f37b8c6

Same setup as `summary-2026-11-15-sonnet-ms-main4048.md`: claude-code + claude-sonnet-5-5, shipped skill installed in the workspace, 1800 s limit, 3 trials per challenge, 21 challenges (c55 left out), 63 runs, cost about $28, no timeouts. `ms` is a release build of main f37b8c6, which includes #4095 (`m[k] = v` may read `k`) and the first-build error saving of #4099. Raw runs: `trials-2026-11-15-sonnet-ms-f37b8c6.jsonl`. The full first-build errors and sources of the 49 failed first builds are in `results/first-builds/<run_id>/` on the machine that ran it (git-ignored).

| Manuscript, Sonnet | main with #4048 (60 runs) | this run (63 runs) |
|---|---:|---:|
| pass | 88% (78-94) | 90% (81-96) |
| first build ok | 28% (19-41) | 22% (14-34) |
| first build ok after `--fix` | 28% (19-41) | 25% (16-37) |

Intervals overlap on every row: #4095 did not visibly change the first-build rate. 49 of 63 runs failed their first build; MS3000 type errors are in 35 of them, MS2001 resolution in 25, MS1000 parse in 17. Weakest challenges (passing trials): c51-lisp-interpreter and c58-mini-vcs 1 of 3, c36-bank-ledger and c59-spreadsheet 2 of 3.

Most common first errors: a standalone `?` on a non-Unit value, unknown members (`String.get`, `List.remove_last`), a returned reference to a new value, `chars` borrowing `line`, parse errors from unclosed parentheses or inline bodies. The full ranking is `ms run bench/agent/report.ms -- results/trials-2026-11-15-sonnet-ms-f37b8c6.jsonl`.
