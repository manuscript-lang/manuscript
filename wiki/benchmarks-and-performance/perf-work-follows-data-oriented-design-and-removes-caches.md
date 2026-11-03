[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Perf work follows data-oriented design and tries a faster design before a cache

Decision (Chinmay, 2026-11-02): ask these four questions of every perf change and every slow design.

1. How would this be rewritten to use data-oriented design?
2. Can a hash table become a flat array? Can pointers become indices into it? Can the most-used data be packed into the upper bits of the index?
3. Caching is not bad in itself, but explore a faster design first. Add or keep a cache only when measurement shows the redesign cannot match it, and record that measurement.
4. Should this array of structures be a structure of arrays?

Reason: a cache hides a slow lookup behind invalidation rules and memory; a flat, index-addressed layout makes the lookup cheap and removes the rules. Measure before and after ([baseline comparison](a-win-needs-a-baseline-comparison-not-just-a-smaller-number.md)); a cache removal must not slow the neighboring control cases.

Worked case (2026-11-03): removing the runtime's large-block free list left JSON parse unchanged but cut `/io` from about 1830 to 1530 req/s (page faults on 1 MiB blocks), so Chinmay kept it. The pile-up behind the memory growth was fixed by [admission control](../runtime/large-write-payloads-take-a-pool-permit-before-the-copy.md) instead.

Apply when: adding or reviewing perf work, a memo/cache/table, or a pointer-heavy structure in the compiler, runtime, or stdlib.
Evidence: [perf-bash](../../skills/perf-bash/SKILL.md), [data-oriented compiler passes](../compiler/compiler-passes-use-the-right-algorithm-and-data-structure-f.md).
Verify: the change shows a same-machine before/after, adds a cache only with a measurement showing no faster design matches it, and states why a flat array or index replaces any hash table or pointer it touches.
