[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

Apply when: optimizing a helper, a lowering path, or a runtime routine.
Evidence: [program results](../../bench/perf/programs/results.md), [kernel baselines](../../bench/perf/kernels/README.md).
Verify: time and allocation counts before and after on one machine; behavior tests unchanged.

Verified (2026-10-31, TOML quoting): batching UTF-8 runs improved ASCII timing by
6.9x but raised whole-process peak RSS by 64% for a large string with one late
escape. Retain large sparse-escape memory controls alongside timing; the accepted
change only removes general radix formatting for known ASCII control escapes.
Evidence: [matched controls and rejected variants](../../bench/perf/toml-quoting/README.md).

Shortest float round trips do not establish byte-identical serialization: equally short,
equally close decimals can use different tie rules. Preserve the previous exact output
with a direct formatter oracle, midpoint families and signed/nonfinite cases before
comparing speed. The JSON float study retained a rejected converter whose dense win
coincided with a reproducible Unicode slowdown; its replacement must pass the same
controls. Evidence: [JSON library controls](../../bench/perf/json-library/README.md).
