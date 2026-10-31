[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

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
escape. Retain large sparse-escape memory controls alongside timing; the accepted
change only removes general radix formatting for known ASCII control escapes.
Evidence: [matched controls and rejected variants](../../bench/perf/toml-quoting/README.md).

Verified (2026-10-31, String reversal): a standard-iterator candidate cut large
reversal times substantially but added 2.5–3.6 ns to empty/one-byte reversals,
regressed normalization/search controls and raised whole-process peak RSS about
6.1%. Reject the complete candidate, retain every adverse result, and distinguish
standalone from combined-change controls. A textual proof that the old fallback
is unchanged does not establish performance equivalence for other operations.
Evidence: [four-state reversal rejection](../../bench/perf/string-reverse-standard/README.md).

Verified (2026-10-31, normalization): ASCII identity shortcuts can win over 200x
on ASCII while slowing Unicode controls by several percent. A content-based
first-byte gate removed one flag but exposed other NFD costs; both were rejected.
Retain complete matrices and composition controls rather than accepting a
removed flag or a clean screen.
Evidence: [both rejected normalization candidates](../../bench/perf/string-normalize-ascii/results-2026-10-31.md).
