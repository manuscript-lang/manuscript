# Agent bench, 2026-11-15: Sonnet, all languages, 3 trials

claude-code (`claude -p`) + claude-sonnet-5-5, 19 challenges in ts, go, rust and ms, three trials per challenge and language (228 runs), `--jobs 4` on a 4-core cloud VM, 1800 s agent limit. `ms` is a release build of main at `87813684`, so this is the baseline before the `ms check --fix` repairs of #4018. The Manuscript workspace has the shipped skill installed (`ms skill -o .claude/skills`); every transcript of the first batch invokes it. Raw runs: `trials-2026-11-15-sonnet.jsonl`; `trials-2026-11-15-sonnet-interrupted.jsonl` holds 15 runs of unfinished cells from before the runner was restarted and is not counted. Reproduce the tables with `ms run bench/agent/report.ms -- bench/agent/results/trials-2026-11-15-sonnet.jsonl`.

c55-jq-lite is left out: its reference solution is 68 KB against 17 to 38 KB for the other large challenges, and it timed out in all four languages on 2026-10-31. Final sources are not committed this time (several Manuscript ones fail `make repo-check`). Cost as reported by the harness: about $68 for the 228 runs.

| | pass (95% CI) | first build ok (95% CI) | turns | cost per passing run |
|---|---:|---:|---:|---:|
| go | 89% (79-95) | 98% (91-100) | 3.7 | $0.22 |
| rust | 86% (75-93) | 100% (94-100) | 3.8 | $0.23 |
| ts | 84% (73-91) | 100% (94-100) | 3.8 | $0.19 |
| ms | 84% (73-91) | 9% (4-19) | 11 | $0.42 |

Pass rates are statistically indistinguishable. The gap is the first build: 52 of 57 Manuscript runs failed it, and a Manuscript run takes about three times the turns and twice the cost. TypeScript has no build step here, so its first-build rate is trivially 100%.

## Why Manuscript's first build fails

Codes in failed builds (MS1000 parse, MS2001 resolution, MS3000 type, MS3001 type), by runs that hit them: MS3000 47, MS2001 32, MS3001 24, MS1000 18, MS3060 5. Reading the 19 transcripts of the first batch, the most common first-error messages were:

- `length` used wrong: compared as a function (`x.length == 5`, about 45 times in total) or called as `.len()` (31 times). The shipped skill never shows `.length()`.
- `none` compared with `==` (12), `??`-style chained unwrap (10).
- Too many positional arguments (8), `?` applied to an Optional (7), bare `return` in a Result function (6).
- Borrow errors: returning a view of an owned value, changing `self` while a `for` borrows it.

Not every run's first error line was captured (the logging landed mid-run); the code counts above cover all runs.

## Exercise problems found

Four challenges failed in every language for reasons the spec did not state, so they measured guessing: c58 `status-fresh` and `files-basic`, c60 `delete-and-ids` and `misc-errors`, c57 `asm-circular-equ`. Specs fixed in #4045 after this run; c58 (0 of 12), c60 and c57 results here are therefore not comparable with later runs.

| challenge | go | ms | rust | ts |
|---|---:|---:|---:|---:|
| c14-dp-suite | 3/3 | 2/3 | 3/3 | 3/3 |
| c51-lisp-interpreter | 2/3 | 3/3 | 3/3 | 3/3 |
| c54-regex-engine | 3/3 | 2/3 | 2/3 | 2/3 |
| c56-make-lite | 3/3 | 3/3 | 2/3 | 2/3 |
| c57-assembler-vm | 3/3 | 1/3 | 3/3 | 2/3 |
| c58-mini-vcs | 0/3 | 0/3 | 0/3 | 0/3 |
| c59-spreadsheet | 3/3 | 2/3 | 2/3 | 3/3 |
| c60-issue-tracker | 1/3 | 2/3 | 1/3 | 0/3 |

All other challenges passed 3 of 3 in every language.
