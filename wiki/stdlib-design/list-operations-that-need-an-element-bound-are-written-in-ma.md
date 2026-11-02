[Wiki](../index.md) › [Standard-library design](index.md)

# List operations that need an element bound are written in Manuscript

Decision: `sum`, `min`, `max` and the comparator-less `sorted()`/`sort()` live in the source half of [collections.ms](../../stdlib/collections/collections.ms), a bundled source module (`@std/collections/collections.ms+source`) every program loads. Each group is a bounded interface (`ListOrder[T: Comparable]`, `ListExtremes[T: Comparable & Clonable]`, one `sum` interface per numeric element type) with `impl ... for List[T]`; a bundled module may extend a native standard type this way, and its methods apply without an import.

Apply when: adding a List operation that depends on an element contract, or changing `sortgen`'s recognized comparator shapes.
Evidence: [collections.ms](../../stdlib/collections/collections.ms), [list-aggregates fixture](../../tests/e2e/testdata/stdlib/list-aggregates.ms), `list.sorted` and `list.sorted_natural` in `bench/perf/stdlib/lists_bench.ms`.
Verify: `make stdlib-bench BENCHFILTER=list.sort` shows `sorted_natural` within noise of `sorted`.
