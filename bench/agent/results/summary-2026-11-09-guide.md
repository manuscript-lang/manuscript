# Agent bench, 2026-11-09: guide refresh, Haiku, ms only

claude-code + claude-haiku-5-5, 20 challenges, Manuscript only, one trial each, `--jobs 4` on a cloud VM (wall time reflects contention). `ms` is a release build of main at `3fbb7cfe`; "after" adds the `ms guide` edits in this change. Raw runs: `trials-2026-11-09-baseline.jsonl`, `trials-2026-11-09-guide.jsonl`. One trial per challenge, so differences of 1-2 runs are within noise.

| | before | after |
|---|---:|---:|
| pass (timeout workspaces that pass counted) | 17/20 | 19/20 |
| pass, strict (timeouts fail) | 15/20 | 18/20 |
| first build ok | 8/20 | 9/20 |
| builds per run | 4.1 | 4.15 |
| agent timeouts (900s) | 3 | 2 |
| failing | c55, c58, c60 | c55 |

Most frequent compile errors in the baseline transcripts, which drove the edits: moving a field or borrow out (`.clone()`), a missing result type after `)` (agents wrote `->`), `!x` instead of `not x`, a `var` parameter called without `var`, unescaped `{`/`}` in strings, `else` after a one-line `if`, `try` outside a `Result` function, `Bytes` without an import. The edits add the brace, `else`, `->`, `not` and Map-insert rules to the cheat sheet. c55-jq-lite times out in every run (throughput, not language fit).

The runner needed two fixes first (`run.ms` promise captures, `core/model.ms` borrow move) and one workaround for a compiler ICE on a borrowed `if` arm passed as a call argument.
