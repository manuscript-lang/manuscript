# Agent bench, 2026-10-31: Haiku, all languages

claude-code (`claude -p`, Claude Code login) + claude-haiku-5-5, all 20 challenges in ts, go, rust and ms, one trial each, built-in runner (`run.py run --jobs 4`, 4-core Intel Xeon @ 2.1 GHz cloud VM, so wall time reflects 4-way contention). `ms` is a release build of main at `09e0eb7e`; `node` 22.23.4. Raw runs: `trials-2026-10-31.jsonl`. Closes #1547.

Before the run the reference solutions failed `run.py oracle` (stale ts `import readFileSync from "node:fs"`, ms `some(...)` and `if var x = m.get(k)`). They were fixed in the same change; the oracle now passes for all 40 reference solutions.

| | ts | go | rust | ms |
|---|---:|---:|---:|---:|
| pass | 17/20 | 17/20 | 15/20 | 15/20 |
| agent timeouts (900s) | 1 | 1 | 1 | 4 |

Timeouts report 0 turns and 0 cost because the killed CLI emits no usage; a timed-out workspace that passes the hidden cases counts as a pass (c51 ms, c59 ms). c55-jq-lite timed out in all four languages while still generating a single large file under contention, so it measures throughput, not language fit.

| challenge | ts | go | rust | ms | ms builds | ms first build |
|---|---|---|---|---|---:|---|
| c03-csv-group-sum | pass 13/13 | pass 13/13 | pass 13/13 | pass 13/13 | 5 | no |
| c05-calculator | pass 13/13 | pass 13/13 | pass 13/13 | pass 13/13 | 6 | no |
| c09-ciphers | pass 14/14 | pass 14/14 | pass 14/14 | pass 14/14 | 4 | no |
| c13-inventory-orders | pass 14/14 | pass 14/14 | pass 14/14 | pass 14/14 | 3 | no |
| c14-dp-suite | FAIL 14/15 | pass 15/15 | pass 15/15 | pass 15/15 | 2 | yes |
| c16-maze-bfs | pass 17/17 | pass 17/17 | pass 17/17 | pass 17/17 | 2 | yes |
| c18-cron-next-runs | pass 17/17 | pass 17/17 | pass 17/17 | pass 17/17 | 4 | no |
| c25-log-analyzer | pass 14/14 | pass 14/14 | pass 14/14 | pass 14/14 | 5 | no |
| c36-bank-ledger | pass 13/13 | pass 13/13 | pass 13/13 | pass 13/13 | 3 | yes |
| c44-unified-diff | pass 22/22 | pass 22/22 | pass 22/22 | pass 22/22 | 4 | no |
| c51-lisp-interpreter | pass 108/108 | pass 108/108 | FAIL 78/108 | pass (timeout) 108/108 | 11 | yes |
| c52-sql-engine | pass 42/42 | pass 42/42 | pass 42/42 | FAIL (timeout) 14/42 | 2 | yes |
| c53-markdown-html | pass 51/51 | pass 51/51 | pass 51/51 | FAIL 50/51 | 4 | no |
| c54-regex-engine | FAIL 39/41 | pass 41/41 | pass 41/41 | pass 41/41 | 5 | no |
| c55-jq-lite | FAIL (timeout) 0/76 | FAIL (timeout) 0/76 | FAIL (timeout) 0/76 | FAIL (timeout) 0/76 | 0 | no |
| c56-make-lite | pass 75/75 | pass 75/75 | FAIL 71/75 | pass 75/75 | 3 | yes |
| c57-assembler-vm | pass 80/80 | pass 80/80 | FAIL 79/80 | FAIL 79/80 | 6 | no |
| c58-mini-vcs | pass 57/57 | FAIL 49/57 | FAIL 56/57 | FAIL 49/57 | 3 | yes |
| c59-spreadsheet | pass 43/43 | pass 43/43 | pass 43/43 | pass (timeout) 43/43 | 4 | no |
| c60-issue-tracker | pass 47/47 | FAIL 46/47 | pass 47/47 | pass 47/47 | 3 | yes |

### By harness and language

| group | runs | pass | first build ok | tokens (in+out) | turns | wall s | cost $ |
|---|---:|---:|---:|---:|---:|---:|---:|
| claude_code / go | 20 | 85% | 90% | 5.28e+05 | 7.59 | 167 | 0.0779 |
| claude_code / ms | 20 | 75% | 40% | 9.68e+05 | 12 | 317 | 0.0996 |
| claude_code / rust | 20 | 75% | 80% | 5.31e+05 | 7.53 | 170 | 0.0731 |
| claude_code / ts | 20 | 85% | 90% | 4.66e+05 | 6.59 | 176 | 0.0704 |

### By language and category

| group | runs | pass | first build ok | tokens (in+out) | turns | wall s | cost $ |
|---|---:|---:|---:|---:|---:|---:|---:|
| go / algorithms | 3 | 100% | 100% | 2.28e+05 | 5.33 | 33.8 | 0.00856 |
| go / applications | 12 | 75% | 83% | 8.03e+05 | 9.33 | 283 | 0.14 |
| go / data | 2 | 100% | 100% | 2.12e+05 | 6 | 32.8 | 0.00836 |
| go / parsing | 1 | 100% | 100% | 1.6e+05 | 4 | 27.4 | 0.00601 |
| go / state-machines | 1 | 100% | 100% | 2.78e+05 | 6 | 54.8 | 0.0125 |
| go / strings | 1 | 100% | 100% | 2.06e+05 | 7 | 36.3 | 0.0073 |
| ms / algorithms | 3 | 100% | 67% | 4.22e+05 | 9 | 71.4 | 0.0151 |
| ms / applications | 12 | 58% | 50% | 1.42e+06 | 12.3 | 587 | 0.192 |
| ms / data | 2 | 100% | 0% | 7.98e+05 | 15 | 104 | 0.0246 |
| ms / parsing | 1 | 100% | 0% | 5.73e+05 | 13 | 51.1 | 0.0138 |
| ms / state-machines | 1 | 100% | 0% | 5.41e+05 | 11 | 103 | 0.0233 |
| ms / strings | 1 | 100% | 0% | 6.07e+05 | 13 | 64.8 | 0.0172 |
| rust / algorithms | 3 | 100% | 100% | 2.11e+05 | 5.33 | 32.7 | 0.00813 |
| rust / applications | 12 | 58% | 67% | 8.74e+05 | 9.57 | 323 | 0.146 |
| rust / data | 2 | 100% | 100% | 2.6e+05 | 6 | 42.4 | 0.00985 |
| rust / parsing | 1 | 100% | 100% | 1.61e+05 | 5 | 22 | 0.00634 |
| rust / state-machines | 1 | 100% | 100% | 2.8e+05 | 7 | 52.8 | 0.0128 |
| rust / strings | 1 | 100% | 100% | 2.53e+05 | 6 | 34.5 | 0.00844 |
| ts / algorithms | 3 | 67% | 100% | 1.86e+05 | 4.5 | 27.5 | 0.00704 |
| ts / applications | 12 | 83% | 83% | 6.58e+05 | 7.9 | 278 | 0.114 |
| ts / data | 2 | 100% | 100% | 1.86e+05 | 5 | 32.4 | 0.00802 |
| ts / parsing | 1 | 100% | 100% | 2.05e+05 | 5 | 26.5 | 0.00736 |
| ts / state-machines | 1 | 100% | 100% | 2.28e+05 | 5 | 47.9 | 0.0109 |
| ts / strings | 1 | 100% | 100% | 1.62e+05 | 4 | 26.6 | 0.00648 |

### By language and tier

| group | runs | pass | first build ok | tokens (in+out) | turns | wall s | cost $ |
|---|---:|---:|---:|---:|---:|---:|---:|
| go / tier 2 | 4 | 100% | 100% | 1.82e+05 | 5.5 | 25.5 | 0.00643 |
| go / tier 3 | 6 | 100% | 100% | 2.34e+05 | 5.5 | 39.9 | 0.00966 |
| go / tier 5 | 10 | 70% | 80% | 9.78e+05 | 10.6 | 356 | 0.177 |
| ms / tier 2 | 4 | 100% | 25% | 5.94e+05 | 12.8 | 67.1 | 0.017 |
| ms / tier 3 | 6 | 100% | 33% | 5.85e+05 | 11.7 | 90.9 | 0.0206 |
| ms / tier 5 | 10 | 50% | 50% | 1.73e+06 | 11.8 | 787 | 0.26 |
| rust / tier 2 | 4 | 100% | 100% | 2.19e+05 | 5.25 | 30.8 | 0.00777 |
| rust / tier 3 | 6 | 100% | 83% | 2.43e+05 | 6.5 | 40.5 | 0.00998 |
| rust / tier 5 | 10 | 50% | 70% | 1.13e+06 | 10.6 | 438 | 0.201 |
| ts / tier 2 | 4 | 100% | 100% | 1.82e+05 | 4.75 | 23.8 | 0.00647 |
| ts / tier 3 | 6 | 83% | 100% | 2e+05 | 4.8 | 38.8 | 0.00909 |
| ts / tier 5 | 10 | 80% | 80% | 7.74e+05 | 8.62 | 338 | 0.141 |
