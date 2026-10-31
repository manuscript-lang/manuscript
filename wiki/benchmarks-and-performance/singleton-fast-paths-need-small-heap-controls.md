[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Singleton fast paths need small-heap controls

Verified (2026-10-31): skipping singleton PriorityQueue self-swaps/sifting improved
one-element batches by about 62%, but a grouped guard made eight-element heaps
a median 22% slower, with all 16 longer pairs slower. Unchanged Queue controls also
regressed; an identical-binary A/A replay stayed near flat. Both patches were rejected.

Apply when: adding a tiny-collection shortcut or accepting a locally measured win.
Evidence: [rejected candidates and complete controls](../../bench/perf/priority-queue-singleton/README.md).
Verify: include empty/singleton/small/large heaps, unchanged workloads, balanced
before/after and A/A trials; preserve regressions and do not tune code placement.
