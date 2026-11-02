[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Perf work follows data-oriented design and removes caches

Decision (Chinmay, 2026-11-02): ask these four questions of every perf change and every slow design.

1. How would this be rewritten to use data-oriented design?
2. Can a hash table become a flat array? Can pointers become indices into it? Can the most-used data be packed into the upper bits of the index?
3. Caching is cope for a slow design. Do not add caches; delete existing ones and redesign the slow part to be fast.
4. Should this array of structures be a structure of arrays?

Reason: a cache hides a slow lookup behind invalidation rules and memory; a flat, index-addressed layout makes the lookup cheap and removes the rules. Measure before and after ([baseline comparison](a-win-needs-a-baseline-comparison-not-just-a-smaller-number.md)); a cache removal must not slow the neighboring control cases.

Apply when: adding or reviewing perf work, a memo/cache/table, or a pointer-heavy structure in the compiler, runtime, or stdlib.
Evidence: [perf-bash](../../skills/perf-bash/SKILL.md), [data-oriented compiler passes](../compiler/compiler-passes-use-the-right-algorithm-and-data-structure-f.md).
Verify: the change shows a same-machine before/after, adds no new cache, and states why a flat array or index replaces any hash table or pointer it touches.
