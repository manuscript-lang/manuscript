# Capture shapes in regex output methods, 2026-10-29

Baseline: `4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192`. This is a fresh
execution-side pass after [the earlier regex work](regex-results-2026-10-29.md).
The new workloads vary the compiled pattern's capture shape. The earlier suite
always used explicit groups for capture collection and named groups for named
capture queries.

A compiled pattern with only its implicit whole-match group needs no submatch
capture work. `captures_all`
previously collected complete spans, then searched those matches again and
allocated capture bookkeeping. It now maps validated spans into singleton rows.
`captures` uses the ordinary first-match query for this shape, avoiding capture
slots and reserving only one result column. Strict match-count validation and
the existing empty-match selection run before the all-row shortcut.

A pattern without named groups always returns an empty named-capture map.
Construction now records that immutable fact; `named_captures` returns immediately
for it. Named patterns retain the original capture-first path and group-index
iteration. The flag is derived from compiled metadata, as are the whole-only
shortcuts. Optional groups that do not participate still retain their empty
columns. No API, error identity, span traversal, regex dialect or expansion parser
changes.

## Method

Linux x86-64 6.18.55, Intel Xeon Platinum 8573C, five exposed CPUs, four-CPU
cgroup quota, 16 GiB memory limit. Rust 1.99.1 (`58cf8f9c3`, 2026-10-13),
regex 1.13.1. Native libraries use Rust release optimization for
`x86_64-unknown-linux-musl`. All generated programs explicitly select
`MS_BACKEND=cranelift` and use `ms bench`'s default Release build type, which
selects optimized MIR and Cranelift `speed`. There is no LLVM-backend comparison.

One release compiler and identical source run against separate preserved native
archives and caches. Seven paired processes alternate before/after order. The initial full run takes
three timed samples per case; the predefined full recheck and focused comparisons
take five. Each follows calibration. CPU 0 affinity is inherited
by every producer. No local tests or builds run during timings. The in-program
`@std/test/bench.ms` harness excludes compiler startup, program startup and input/regex
construction. The cached flag adds an allocation-free metadata scan during
construction, stopping at the first name. Construction latency was not measured.

Every row, first-capture list and named map is checked completely against an
independent expected value, and a checksum/length is consumed with `keep`.
The budget-error control checks the exact `RegexError.LimitExceeded` value.
Producer failure, absent/duplicate identities, changed operation counts or failed
cases reject the comparison. Every case reports one complete operation. Raw JSONL
records retain each process's sample statistics; distribution tables summarize
the seven process medians and their population CV.

## Runtime results

Both full comparisons use the final cached-flag candidate and identical 20-case source.
Each entry below is the canonical ratio of the seven process medians; lower is faster.

| case | three samples per process | five-sample full recheck |
| --- | ---: | ---: |
| whole-only rows, 1 | 0.599x | 0.753x |
| whole-only rows, 128 | 0.578x | 0.639x |
| whole-only rows, 2,000 | 0.607x | 0.720x |
| whole-only rows, one 65,536-byte match | 0.570x | 0.572x |
| first whole-only short hit | 0.827x | 0.771x |
| named query, whole-only pattern | 0.159x | 0.158x |
| named query, unnamed explicit groups | 0.145x | 0.161x |

The 2,000-row call falls from 623.7 to 378.4 microseconds in the first full run,
and 656.4 to 472.5 microseconds in the recheck. Removing the second search over
a 65,536-byte whole match repeatedly takes about 0.57x baseline time. The large
no-named-group miss queries fall from roughly 164–174 microseconds to about
40 nanoseconds because their empty output is known without searching.
These cases have substantial repeated work savings; the exact ratios remain
specific to this host and harness.

The [three-sample full table](results/regex-cardinality-2026-10-29/full-3samples/results.md),
[five-sample recheck](results/regex-cardinality-2026-10-29/full-5samples/results.md)
and their distribution tables retain every case, including controls that look
slower. Some process-median CVs exceed 100% in the first run and 80% in the
recheck. The initial large grouped-row slowdown (1.785x for one row) does not
reproduce in either the [grouped focus](results/regex-cardinality-2026-10-29/grouped-focused/results.md)
(1.048x / 0.947x for one / 2,000 rows) or full recheck (0.964x / 1.017x).

Smaller baseline increases remain uncertain: named hits measure 1.091x / 1.077x,
and long first captures 1.175x / 1.096x in the two full runs, with overlapping,
wide process ranges. One final predefined isolation compared the retained
32-byte whole-only candidate with the 40-byte cached-flag candidate, changing
no inputs or capture-method source bodies. [Named hits](results/regex-cardinality-2026-10-29/flag-isolation-named/results.md)
measure 0.998x and [long first captures](results/regex-cardinality-2026-10-29/flag-isolation-first-long/results.md)
0.994x. That comparison does not reproduce an added flag cost; it does not erase
the original-baseline uncertainty. Tiny empty and budget-error controls also
vary, even where the source returns before the new shortcut.

The [environment and immutable input hashes](results/regex-cardinality-2026-10-29/environment.json)
identify the compiler, benchmark, source, archives and wrappers. They were
verified unchanged after both full runs and wrapper isolations. Every full run
contains all 20 source-declared cases in every trial. Distribution tables keep
the canonical ratio-of-medians tables and add paired-ratio medians only as a
diagnostic. All earlier results, including the initial narrower 16-case
comparison, remain available. The data supports the specific whole-output and
empty-named-output savings; it does not establish zero runtime cost in every
unchanged workload.

## Allocations and persistent cost

The [host allocation probe](regex-cardinality-allocation-probe.md) checks 24 cases
three times, with one warmup per case. All three trials are identical; complete
outputs/checksums match and every call returns to zero extra live bytes after
output destruction. Counts use Rust `System`, with full successful request sizes
and logical live capacities. They do not measure generated-runtime RSS or hidden
transient storage inside `System::realloc`.

| case | allocations before / after | reallocations before / after | requested bytes before / after | logical peak bytes before / after |
| --- | ---: | ---: | ---: | ---: |
| whole-only rows, 1 | 5 / 4 | 0 / 0 | 207 / 119 | 207 / 119 |
| whole-only rows, 2,000 | 4,003 / 4,002 | 18 / 9 | 225,696 / 175,472 | 143,936 / 142,768 |
| first whole-only hit | 3 / 2 | 0 / 0 | 119 / 31 | 119 / 31 |
| first whole-only miss | 1 / 0 | 0 / 0 | 16 / 0 | 16 / 0 |
| named query, unnamed explicit groups | 1 / 0 | 0 / 0 | 48 / 0 | 48 / 0 |

The validated-span map also knows its exact output row count and avoids outer
vector growth. Grouped capture/row/named controls, row misses and exceeded budgets
have unchanged allocation counts. [All probe cases](results/regex-cardinality-2026-10-29/allocation-comparison.md),
[raw before](results/regex-cardinality-2026-10-29/allocation-baseline.txt) and
[raw after](results/regex-cardinality-2026-10-29/allocation-candidate.txt) are retained.

Persistent storage increases: the production-configuration wrapper is **32 to
40 bytes**, with alignment 8, on the measured x86-64 host. The cached boolean
therefore costs eight bytes per compiled wrapper, including padding. The per-call
counts exclude that setup storage and metadata scan. No extra allocation is
needed to compute the flag, and compiled-pattern internals are unchanged.

## Rejected name scan and fresh coverage

An intermediate candidate scanned names before each search, then reused the
same peekable iterator. It avoided anonymous-pattern searches without a flag,
but the late-name fast-miss control regressed **159.9 to 218.1 ns**, 1.364x,
in seven pairs of three samples. That control has 128 leading unnamed optional
groups before one named group. The cached flag removes that repeated scan and
restores capture-first work for named patterns. The
[rejected comparison](results/regex-cardinality-2026-10-29/rejected-name-scan/results.md),
[distributions](results/regex-cardinality-2026-10-29/rejected-name-scan/distributions.md)
and exact source snapshot are retained. This comparison uses the earlier
whole-only shortcut as its baseline; it does not compare directly with main.

After the fixes, an independent Sol 6.1 pass inspected boolean matching, both
span selectors, find-all/span queries, first/all/named captures, strict limits,
literal/template replacement and the unchanged split contracts. No further new
reproducible actionable item emerged in that bounded pass. A zero-budget-only
specialization would remove one small span allocation on an error path while
adding a branch to ordinary calls; it has no demonstrated relevant hot workload
and was not promoted. Prior limited-split, scratch retention, searcher and ASCII
tradeoffs remain separate; this pass does not reopen them or change regex engines.
This is coverage evidence for the inspected paths, not proof that every workload
has reached its fastest possible implementation.

## Reproduction

Run from the candidate checkout with its benchmark additions and fresh temporary
paths. The commands stop on errors, including an already-existing worktree. Build
the old runtime separately; both variants use the same current compiler and source.
Keep runtime builds sequential because `xtask` publishes one archive per checkout.

```sh
set -eu
git worktree add /tmp/ms-regex-cardinality-before 4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192
(cd /tmp/ms-regex-cardinality-before && cargo xtask runtime)
cp /tmp/ms-regex-cardinality-before/target/ms-native/libms_native.a /tmp/regex-cardinality-before.a
cargo xtask runtime
cp target/ms-native/libms_native.a /tmp/regex-cardinality-after.a
cargo build --release --locked -p ms-cli
export REGEX_COMPILER="$(pwd)/target/release/ms"
export REGEX_BEFORE_RUNTIME=/tmp/regex-cardinality-before.a
export REGEX_AFTER_RUNTIME=/tmp/regex-cardinality-after.a
export REGEX_BEFORE_CACHE=/tmp/regex-cardinality-before-cache
export REGEX_AFTER_CACHE=/tmp/regex-cardinality-after-cache
cat > /tmp/regex-cardinality-before-ms <<'SH'
#!/bin/sh
exec env MS_BACKEND=cranelift MS_RT_LIB="$REGEX_BEFORE_RUNTIME" MANUSCRIPT_CACHE_DIR="$REGEX_BEFORE_CACHE" "$REGEX_COMPILER" "$@"
SH
cat > /tmp/regex-cardinality-after-ms <<'SH'
#!/bin/sh
exec env MS_BACKEND=cranelift MS_RT_LIB="$REGEX_AFTER_RUNTIME" MANUSCRIPT_CACHE_DIR="$REGEX_AFTER_CACHE" "$REGEX_COMPILER" "$@"
SH
chmod +x /tmp/regex-cardinality-before-ms /tmp/regex-cardinality-after-ms
taskset -c 0 python3 bench/perf/compare_stdlib.py \
  --before /tmp/regex-cardinality-before-ms --after /tmp/regex-cardinality-after-ms \
  --filter regex.cardinality --repeats 7 --samples 3 --output /tmp/regex-cardinality-comparison
```

For the initial narrower 16-case run or rejected name-scan experiment, use the
retained benchmark/source snapshots and archive identities in the evidence
folder. The final 20-case source is `regex_cardinality_bench.ms`. The external
allocation instructions include the complete harness and pinned standalone lock;
that documented setup was built and all 72 trial rows per variant reproduced.

## Validation and limits

- Independent Sol 6.1 implementation and allocation review found no correctness blocker.
- `cargo test --release --locked -p ms-std-regex`: 10 unit tests and recorded regex oracle passed.
- Called regex fixture: seven tests passed in both Release and Debug.
- `cargo fmt --all --check`, workspace clippy with warnings denied, repository
  checks, license freshness, and workspace Rust doctests passed. The 20-module benchmark project checks.
- Frozen corpus: 2,393/2,393 selected fixtures passed; corpus lint checked 4,153
  fixtures with no problems.
- Full workspace nextest with fail-fast disabled: 1,218 passed, one unrelated
  compiler timing-threshold failure, one existing ignored test skipped. The
  timing test took 22.188 seconds while conformance was also running; its isolated
  rerun passed in 6.483 seconds. No source in that compiler path changed and no
  tests were weakened or disabled. All 1,219 runnable tests passed across the
  full run and isolated recheck. An earlier formatter failure in the new fixture
  was corrected; the complete run passed that repository-formatting test.
- New Rust regressions cover whole-only outputs, no matches, zero-width adjacency,
  anchors/boundaries, negative/exact/exceeded limits, optional-group columns,
  unnamed groups and a named group after 128 unnamed groups. The new called
  source test exercises the public methods and strict budget through native bindings.
- The documented allocation reproduction was built and run: all 72 trial rows
  and headers per variant matched the independent probe; its fenced harness hash
  matches the measured harness.

Windows/macOS execution, their performance, LLVM generated-code timings,
regex-construction latency and generated musl/StdHeap RSS were not measured here.
Individual Actions conclusions and main-platform CI are not established by these
local results. No workflow API reads/dispatches, approval bypasses or changes to
excluded compiler, ownership, HTTP or Windows CI paths are involved.
