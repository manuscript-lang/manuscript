# Agent bench, 2026-11-15: Sonnet, Manuscript only, after #4018

Same setup as `summary-2026-11-15-sonnet.md`: claude-code + claude-sonnet-5-5, 19 challenges, 3 trials each (57 runs), shipped skill installed in the workspace, 1800 s limit. `ms` is a release build of main that includes the `ms check --fix` repairs of #4018 and the repaired specs of #4045, but not the skill examples of #4048 (the skill is embedded in the compiler, so this run still teaches the old text). Raw runs: `trials-2026-11-15-sonnet-ms-fix.jsonl`. Cost about $24.

This run also records `first build after --fix`: when a build fails, `check.sh` tries `ms check ms.toml --fix` on a copy and logs whether the copy then builds. The agent's files are untouched.

| Manuscript, Sonnet | before #4018 (228-run baseline) | this run |
|---|---:|---:|
| pass | 84% (73-91) | 84% (73-91) |
| first build ok | 9% (4-19) | 21% (12-33) |
| first build ok after `--fix` | not measured | 25% (15-37) |
| builds per run | 3.74 | 2.82 |
| turns per run | 12.1 | 11.4 |

The first-build rate rose from 9% to 21%; the intervals overlap slightly, so treat it as likely, not certain. `--fix` on its own adds only four points: most remaining first-build failures are type errors it cannot repair (MS3000 in 39 of 57 runs, MS1000 parse errors in 20, MS2001 resolution in 16, MS3001 in 7).

Most common first errors now: a bare `return` in a function that returns a Result, `?.` used on a Result, a quote inside a string interpolation that opens nested text, chained Optional unwrap, borrow errors (a returned view of an owned value, a value moved and used again), a standalone `?` needing a Unit success value.

Pass rates by challenge changed with the fixed specs: c58-mini-vcs now 1 of 3 (was 0 of 3), c60-issue-tracker 3 of 3 (was 2 of 3), c57-assembler-vm 3 of 3 (was 1 of 3). c51-lisp-interpreter fell to 1 of 3 (was 3 of 3) and c54-regex-engine to 1 of 3 (was 2 of 3); with three trials these swings are within noise.
