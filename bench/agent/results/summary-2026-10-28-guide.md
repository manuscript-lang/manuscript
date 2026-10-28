# Manuscript agent bench, 2026-10-28 (guide update): Haiku rerun, ms only

claude-code + claude-haiku-5-5, all 20 challenges, Manuscript only, one trial each, built-in runner (`run.py run --jobs 4`, 4-core machine, so wall time reflects contention). The `ms` binary is a release build of the branch that became PR #1879 (main at `09d372ca` plus the rewritten `ms guide` cheat sheet). The only intended difference from `summary-2026-10-28.md` (main at `87d92d70`) is the guide, but main also moved between the two runs. Raw runs: `trials-2026-10-28-guide.jsonl`. "Before" is `trials-2026-10-28.jsonl`.

| | before | after |
|---|---:|---:|
| pass (timeout workspaces that pass hidden cases counted) | 17/20 | 18/20 |
| pass, strict (timeouts fail) | 14/20 | 17/20 |
| small (c03-c44) pass | 10/10 | 10/10 |
| large (c51-c60) pass | 7/10 | 8/10 |
| first build ok | 5/20 | 9/20 |
| builds per run (mean) | 4.0 | 3.6 |
| agent timeouts (900s) | 4 | 2 |

| challenge | before | after | cases after | turns before | turns after | first build after |
|---|---|---|---|---:|---:|---|
| c03-csv-group-sum | pass | pass | 13/13 | 16 | 23 | no |
| c05-calculator | pass | pass | 13/13 | 15 | 8 | no |
| c09-ciphers | pass | pass | 14/14 | 15 | 15 | yes |
| c13-inventory-orders | pass | pass | 14/14 | 14 | 13 | no |
| c14-dp-suite | pass | pass | 15/15 | 12 | 14 | no |
| c16-maze-bfs | pass | pass | 17/17 | 8 | 12 | no |
| c18-cron-next-runs | pass | pass | 17/17 | 24 | 15 | yes |
| c25-log-analyzer | pass | pass | 14/14 | 13 | 13 | no |
| c36-bank-ledger | pass | pass | 13/13 | 10 | 13 | no |
| c44-unified-diff | pass | pass | 22/22 | 14 | 10 | yes |
| c51-lisp-interpreter | pass (timeout) | pass (timeout) | 108/108 | n/a | n/a | yes |
| c52-sql-engine | pass | pass | 42/42 | 43 | 31 | yes |
| c53-markdown-html | pass | pass | 51/51 | 39 | 26 | yes |
| c54-regex-engine | pass | pass | 41/41 | 42 | 32 | yes |
| c55-jq-lite | FAIL (timeout) | FAIL (timeout) | 0/76 | n/a | n/a | no |
| c56-make-lite | pass (timeout) | pass | 75/75 | n/a | 29 | no |
| c57-assembler-vm | pass | pass | 80/80 | 31 | 31 | no |
| c58-mini-vcs | FAIL (56/57) | pass | 57/57 | 24 | 40 | yes |
| c59-spreadsheet | pass (timeout) | pass (timeout) | 43/43 | n/a | n/a | yes |
| c60-issue-tracker | FAIL (46/47) | FAIL (46/47) | 46/47 | 27 | 44 | no |

Caveats:

- Turns, tokens, time and cost average over passing trials with recorded usage: 14 of 17 before (three timed-out passes have none) and 17 of 18 after (only c51 has none). That makes the means below not like-for-like; the after means include the slow large challenges the before means omitted.
- One trial per cell; differences of one or two challenges are within noise. c60 misses the same single hidden case in both runs; c55 times out with nothing that builds in both.
- Mean turns are flat (21.1 before, 22.1 after) and the guide did not reduce them. The gain is in first-build success (25% to 45%) and fewer timeouts.

## Comparison with other languages

Other languages are from the 2026-10-18 baseline (`leaderboard-2026-10-18.md`, same harness and model, one trial per challenge, not rerun). Agent tokens are input including cache reads plus output.

| language | pass | first build ok | agent tokens | output tokens | turns | wall s | cost |
|---|---:|---:|---:|---:|---:|---:|---:|
| TypeScript (10-18) | 19/20 | 80% | 710k | 50k | 8.4 | 215 | $0.096 |
| Rust (10-18) | 18/20 | 85% | 538k | 53k | 7.4 | 213 | $0.102 |
| Go (10-18) | 18/20 | 80% | 673k | 49k | 8.4 | 211 | $0.103 |
| Manuscript (10-18) | 13/20 | 45% | 4468k | 96k | 33.8 | 452 | $0.378 |
| Manuscript (10-28) | 17/20 | 25% | 2061k | 50k | 21.1 | 242 | $0.180 |
| Manuscript (10-28, guide update) | 18/20 | 45% | 2445k | 64k | 22.1 | 310 | $0.234 |

Manuscript with the new guide passes as many challenges as Rust and Go (18/20) and has a first-build rate back at the 10-18 level, but it still uses about 3.5-4.5x the tokens and about 3x the turns of the other languages.
