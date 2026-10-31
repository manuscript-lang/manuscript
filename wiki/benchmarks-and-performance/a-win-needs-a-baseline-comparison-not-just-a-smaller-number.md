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
