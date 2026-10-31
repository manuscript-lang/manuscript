[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

Fixed-set validation optimizations must preserve admission order as well as accepted
values: TOML checks original byte limits, normalizes CRLF, then reports the first
invalid control before grammar errors. Cover every ASCII/C1 value and Unicode
locations when testing a regex replacement. Include structural parser controls
alongside writers: one TOML scan form improved tiny parsing but incurred repeatable
writer costs; another improved tiny parsing 2.59x but regressed arrays of 128 tables
1.75% (11/12 long paired trials). Both were rejected. Evidence: [TOML admission controls](../../bench/perf/toml-control-scan/README.md).

Apply when: optimizing a helper, a lowering path, or a runtime routine.
Evidence: [program results](../../bench/perf/programs/results.md), [kernel baselines](../../bench/perf/kernels/README.md).
Verify: time and allocation counts before and after on one machine; behavior tests unchanged.

Verified (2026-10-31): adding a scalar prefix before vector byte search preserved
nearby hits but regressed empty/end-start searches by 1–1.6 ns until an empty-range
guard bypassed search setup; a scalar-only one-byte miss still paid about 1 ns
until its empty suffix bypassed vector search too. Include hits at the prefix boundary,
nonzero starts, empty inputs and exact-end starts alongside long misses. The
[byte-search report](../../bench/perf/bytes-index/README.md) retains the rejected
candidate and all distributions; [called tests](../../tests/e2e/testdata/stdlib/bytes-index-search.ms)
pin offsets and high-bit bytes. Opaque Rust benchmark wrappers add tiny-call
overhead, so their nanosecond comparisons alone do not establish language parity.

Verified (2026-10-31, TOML quoting): batching UTF-8 runs improved ASCII timing by
6.9x but raised whole-process peak RSS by 64% for a large string with one late
escape. Retain large sparse-escape memory controls alongside timing. The initially
accepted fixed-digit helper was later reverted after final main exposed common-path
regressions of about 7–13%; isolated gains do not establish combined acceptance.
See the [final replay](../../bench/perf/toml-quoting/final-main-replay.md).
Evidence: [matched controls and rejected variants](../../bench/perf/toml-quoting/README.md).

Verified (2026-10-31, pure utilities): a path candidate combining parse-copy
removal with a different reverse scan doubled long-basename parse time in all
24 pairs. Restore that copy and scan before retaining separate extension,
dot-count and normalization improvements. URL shortcuts also improved long
literal inputs while regressing small escaped inputs; a streaming decoder added
an allocation on malformed escapes that previously allocated nothing. Keep
short/long, sparse/dense, early/late error and allocation controls together.
An initial allocation replay copied a stale executable from another Cargo
target directory; use the explicit build target and verify artifact identities.
Evidence: [complete utility controls and rejected candidates](../../bench/perf/pure-utilities/README.md).

Verified (2026-10-31, normalization): ASCII identity shortcuts can win over 200x
on ASCII while slowing Unicode controls by several percent. A content-based
first-byte gate removed one flag but exposed other NFD costs; both were rejected.
Retain complete matrices and composition controls rather than accepting a
removed flag or a clean screen.
Evidence: [both rejected normalization candidates](../../bench/perf/string-normalize-ascii/results-2026-10-31.md).
