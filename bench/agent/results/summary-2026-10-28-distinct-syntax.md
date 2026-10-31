# Manuscript agent bench, 2026-10-28 (distinct surface syntax): Haiku rerun, ms only

claude-code + claude-haiku-5-5, all 20 challenges, Manuscript only, one trial each, built-in runner (`run.py run --jobs 4`, 4-core machine, so wall time reflects contention). The `ms` binary is a release build of PR #1897 (main at `23129640b` plus the distinct surface: `fn`, `true`/`false`, `unit`, `else if`, `if c: a else: b`, plain interpolating strings, `import A from "p"`, arm patterns without `case`) with the converted `ms guide`. The comparison point is `summary-2026-10-28-guide.md` (Python-aligned surface, same model and harness). Raw runs: `trials-2026-10-28-distinct-syntax.jsonl`, sources in `sources/`.

The run was interrupted by a session restart after 16 trials; c56, c57, c59 and c60 were launched again with the same command and tag, so those four ran with less contention than the rest.

| | Python-aligned (guide) | distinct syntax |
|---|---:|---:|
| pass (timeout workspaces that pass hidden cases counted) | 18/20 | 17/20 |
| pass, strict (timeouts fail) | 17/20 | 16/20 |
| small (c03-c44) pass | 10/10 | 10/10 |
| large (c51-c60) pass | 8/10 | 7/10 |
| first build ok | 9/20 | 7/20 |
| builds per run (mean) | 3.6 | 3.8 |
| agent timeouts (900s) | 2 | 2 |
| mean turns (passing, with usage) | 22.1 | 21.7 |
| mean agent tokens | 2445k | 2314k |
| mean cost | $0.234 | $0.220 |

| challenge | result | cases | turns | first build |
|---|---|---|---:|---|
| c03-csv-group-sum | pass | 13/13 | 11 | no |
| c05-calculator | pass | 13/13 | 13 | no |
| c09-ciphers | pass | 14/14 | 19 | no |
| c13-inventory-orders | pass | 14/14 | 17 | no |
| c14-dp-suite | pass | 15/15 | 11 | no |
| c16-maze-bfs | pass | 17/17 | 11 | no |
| c18-cron-next-runs | pass | 17/17 | 17 | no |
| c25-log-analyzer | pass | 14/14 | 11 | no |
| c36-bank-ledger | pass | 13/13 | 10 | no |
| c44-unified-diff | pass | 22/22 | 17 | no |
| c51-lisp-interpreter | pass | 108/108 | 53 | yes |
| c52-sql-engine | FAIL (agent killed, exit -9) | 11/42 | n/a | yes |
| c53-markdown-html | pass | 51/51 | 18 | no |
| c54-regex-engine | pass | 41/41 | 31 | yes |
| c55-jq-lite | FAIL (timeout) | 0/76 | n/a | no |
| c56-make-lite | pass | 75/75 | 42 | yes |
| c57-assembler-vm | pass | 80/80 | 33 | yes |
| c58-mini-vcs | pass | 57/57 | 33 | yes |
| c59-spreadsheet | pass (timeout) | 43/43 | n/a | yes |
| c60-issue-tracker | FAIL | 46/47 | 35 | no |

Caveats:

- One trial per cell; a difference of one or two challenges is within noise. This run does not show a pass-rate or efficiency change from the new surface.
- c52 was killed by the OS (`exit_code -9`, no usage recorded) after 608s with a build that passed 11/42 cases; it passed 42/42 in the previous run. It is counted as a failure and not rerun, so the 17/20 may understate the surface.
- c55 times out with nothing that builds and c60 misses the same single hidden case, both as in the previous run.
- Means average over passing trials with recorded usage: 16 of 17 passing trials (c59 timed out with no usage), against 17 of 18 before.

## Comparison with other languages

Other languages are from the 2026-10-18 baseline (`leaderboard-2026-10-18.md`, same harness and model, one trial per challenge, not rerun). Agent tokens are input including cache reads plus output.

| language | pass | first build ok | agent tokens | output tokens | turns | wall s | cost |
|---|---:|---:|---:|---:|---:|---:|---:|
| TypeScript (10-18) | 19/20 | 80% | 710k | 50k | 8.4 | 215 | $0.096 |
| Rust (10-18) | 18/20 | 85% | 538k | 53k | 7.4 | 213 | $0.102 |
| Go (10-18) | 18/20 | 80% | 673k | 49k | 8.4 | 211 | $0.103 |
| Manuscript (10-18) | 13/20 | 45% | 4468k | 96k | 33.8 | 452 | $0.378 |
| Manuscript (10-28, guide update) | 18/20 | 45% | 2445k | 64k | 22.1 | 310 | $0.234 |
| Manuscript (10-28, distinct syntax) | 17/20 | 35% | 2314k | 61k | 21.7 | 305 | $0.220 |

The distinct surface is neutral on this suite: pass rate and cost are within one challenge and a few percent of the Python-aligned run, and Manuscript still uses about 3.5-4.5x the tokens and 3x the turns of the other languages. The case for the change rests on the removed Python habits and the targeted diagnostics, not on this number.
