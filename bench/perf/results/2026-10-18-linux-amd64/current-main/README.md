# Current-main performance evidence

2026-10-18 UTC; baseline `2b4962d19c4856efbcc3d8a156578ea9e466d9b7`.
The final source/binary hashes are in environment.json. The parent identifies
the implementation before the final polling boundary; the recorded source hashes
identify that boundary exactly. All code and evidence are committed together.

- programs-before/after: 30 balanced trials against one shared Go control, all
  six execution orders. Regenerate tables with `python3 ../../../programs/table.py
  programs-after.txt 30` from this directory.
- stdlib-before/after: 30 executions per revision, alternating execution order;
  66 distinct cases and identical operation counts in every successful process.
- poll-only-* isolates the final Poll/PollIndex helper against the preceding
  PR implementation. Program trials:30; stdlib trials:15 per revision.
- rejected-global-cancel-* isolates the rejected CheckCancelled annotation.
  Program trials:30; stdlib trials:15 per revision. The production change leaves
  CheckCancelled unchanged and only outlines periodic polling's call.
- statistics.json: paired bootstrap ratios of medians and 95% percentile
  intervals (5000 resamples, seed142). Null intervals mean rounded zero library
  medians prevented a ratio. An interval containing1 is inconclusive, not proof
  of equivalence; native program rows have unrounded elapsed times.
- list-get-paths.txt: seven alternating before/after microbenchmark samples,
  200ms each, List_Get fast wrapper only; both controls have ordinary inlining.
  Positive/negative/default paths are all recorded, including the negative-index
  tradeoff. This isolated earlier-main experiment is not the whole-change run.
- poll-inline.txt: pinned compiler costs and actual native traversal call-site
  inlining for the same private helper boundary.

No correctness tests or compiler jobs ran concurrently with measured trials.
The Go control uses ordinary handwritten operations and normal inlining; maps
have different documented ordering/diagnostic guarantees. Read the report's
remaining gaps and regressions before interpreting any aggregate parity claim.

The final native program binary intentionally has the same SHA-256 as the
pre-polling-change program: rebuilding an unstripped executable from the new
runtime workspace confirms no Poll, PollIndex or pollCancelled symbol is linked
by these ten programs. The stdlib binary does change and exercises those paths.
The experimental overlay binaries were built directly with ordinary Go build
and retain Go build IDs; native replay outputs omit build IDs. This metadata
and source-position distinction limits interpretation of small experimental
program differences. The final tables use native builds on both revisions.
