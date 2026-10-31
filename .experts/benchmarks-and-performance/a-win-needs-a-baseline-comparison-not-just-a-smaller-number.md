[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A win needs a baseline comparison, not just a smaller number

Verified: keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation. Checked arithmetic is language behavior, so a control that omits overflow checks diagnoses cost but does not change the baseline. Reject a candidate that moves a material gap into another workload, and retain its measurements. Prefer removing unobservable work and allocations over placement tuning.

Apply when: optimizing a helper, a lowering path, or a runtime routine.
Evidence: [program results](../../bench/perf/programs/results.md), [kernel baselines](../../bench/perf/kernels/README.md).
Verify: time and allocation counts before and after on one machine; behavior tests unchanged.

Verified (2026-10-29, regex templates): reusing a temporary string cut allocation
calls but raised logical peak live allocation by 33% when a large first expansion
was followed by many small ones. Expanding directly into the result removed the
temporary and lowered that peak instead. Include changing-size output cases when
reusing scratch capacity; allocation counts alone do not establish a memory win.
The [regex report](../../bench/perf/stdlib/regex-results-2026-10-29.md) and its external
counting probe distinguish logical capacity from generated-program RSS.

Verified (2026-10-29, capture shapes): checking named-group metadata before
searching avoided work for anonymous patterns but slowed a named-pattern fast
miss by 36% when many unnamed groups preceded its first name. A flag computed
once during regex construction removed that repeated scan at a measured eight
bytes of persistent wrapper storage. Include early misses and setup storage
when promoting metadata checks into a hot path; successful matches and per-call
allocation counts alone miss this tradeoff. The
[capture-shape report](../../bench/perf/stdlib/regex-cardinality-results-2026-10-29.md)
retains the rejected comparison, final controls and allocation probe.

---
Topics: [Performance](../topics/performance.md)
