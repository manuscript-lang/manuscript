# Manuscript agent bench, 2026-10-28 (ownership examples): Haiku rerun, four challenges

claude-code + claude-haiku-5-5, Manuscript only, one trial each, `run.py run --jobs 4`. Follows `summary-2026-10-28-distinct-syntax.md`: the `ms guide` ownership lines were rewritten as short code (`xs.append(s.clone())`, `names.append(u.name.clone())`, `let` vs `var`, `ref`, `var` parameters), and four verified wrong/right pairs were added to the common-mistakes list. The guide got smaller (5120 to 4929 bytes). Only the challenges that failed or ran longest were rerun: c52, c55, c56, c60. Raw runs: `trials-2026-10-28-ownership-examples.jsonl`.

| challenge | before | after | cases after | turns before | turns after |
|---|---|---|---|---:|---:|
| c52-sql-engine | FAIL (agent killed, exit -9) | pass | 42/42 | n/a | 27 |
| c55-jq-lite | FAIL (timeout) | FAIL (timeout) | 0/76 | n/a | n/a |
| c56-make-lite | pass | pass | 75/75 | 42 | 23 |
| c60-issue-tracker | FAIL (46/47) | FAIL (46/47) | 46/47 | 35 | 39 |

Caveats:

- Four trials, one each. The c52 "before" failure was an OS kill, not a model error, so only c56's turn count (42 to 23) is a like-for-like change, and one trial cannot separate it from noise.
- Compiler messages about moves, mutating a `let` and missing `var`/`ref` appear far less often in the c52, c55 and c56 transcripts (counted by matching message text, which repeats within a run): 44 to 6, 34 to 8 and 24 to 8. c60 went from 34 to 43.
- c55 and c60 fail for reasons unrelated to ownership, as in every earlier run.
