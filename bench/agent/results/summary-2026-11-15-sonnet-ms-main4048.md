# Agent bench, 2026-11-15: Sonnet, Manuscript only, main with #4048

Same setup as `summary-2026-11-15-sonnet-ms-fix.md`: claude-code + claude-sonnet-5-5, shipped skill installed in the workspace, 1800 s limit, 3 trials per challenge. `ms` is a release build of main (af884fdd) that includes the skill examples of #4048 (`.length()`, borrow errors), plus the new tasks c61 (dependency resolver) and c63 (edit an existing program). c55-jq-lite was left out (a 3600 s task at about $5 a run). Three cells have fewer than 3 trials (c51, c52, c53 have 5 each), 60 runs in all. Raw runs: `trials-2026-11-15-sonnet-ms-main4048.jsonl`. Cost about $25. No run timed out.

| Manuscript, Sonnet | before #4048 (`-ms-fix`, 57 runs) | this run (60 runs) |
|---|---:|---:|
| pass | 84% (73-91) | 88% (78-94) |
| first build ok | 21% (12-33) | 28% (19-41) |
| first build ok after `--fix` | 25% (15-37) | 28% (19-41) |

The task sets differ (this run adds c61 and c63), so the comparison is loose. Intervals overlap on every row: #4048 may help, but this run does not show it. `--fix` adds nothing here. 43 of 60 runs failed their first build; MS3000 type errors are in 34 of them, MS1000 parse errors in 21, MS2001 resolution in 17.

Weakest challenges (passing trials): c58-mini-vcs and c51-lisp-interpreter 2 of 6 or 5, c54-regex-engine 3 of 6. The new tasks passed 3 of 3 each. The edit task c63 passes its first build 3 of 3, but edit agents often never run `./check.sh`, so it says little about first builds.

Most common first errors: expected-an-expression parse errors, `@std/io` import names (`io`, `read_all` not exported), `chars` borrowing `line`, `var lines` borrowing `text.lines(..)` mutably, too many positional arguments. Full code ranking and message table: `ms run bench/agent/report.ms -- results/trials-2026-11-15-sonnet-ms-main4048.jsonl`.
