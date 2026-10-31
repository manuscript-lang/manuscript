[Wiki](../index.md) › [Standard-library design](index.md)

# List operations that need an element bound are written in Manuscript

Decision: `sum`, `min`, `max` and the comparator-less `sorted()`/`sort()` live in the source half of [collections.ms](../../stdlib/collections.ms), a bundled source module (`@std/collections.ms+source`) every program loads. Each group is a bounded interface (`ListOrder[T: Comparable]`, `ListExtremes[T: Comparable & Clonable]`, one `sum` interface per numeric element type) with `impl ... for List[T]`; a bundled module may extend a native standard type this way, and its methods apply without an import. A `List[T]` has the operations only when `T` meets the bound. Native `sorted`/`sort` keep a required `compare`; when a native and a source operation share a name, the call's argument count picks one. `Float.compare` must treat NaN as equal to itself and above every value, or float sorts are inconsistent. A file with native inherent methods and bodies is split at load by `split_mixed` in `ms-check/src/stdlib.rs`: bodied contract impls and the interfaces only they implement become the `+source` module, and a bodied inherent `impl List[T]:` method works directly: the split rewrites it to a generated interface plus contract impl, while a bounded or defaulted operation still needs an explicit interface (see `proposals/mixed-native-source-modules.md`).

Apply when: adding a List operation that depends on an element contract, or changing `sortgen`'s recognized comparator shapes.
Evidence: [collections.ms](../../stdlib/collections.ms), [list-aggregates fixture](../../tests/e2e/testdata/stdlib/list-aggregates.ms), `list.sorted` and `list.sorted_natural` in `bench/perf/stdlib/lists_bench.ms`.
Verify: `make stdlib-bench BENCHFILTER=list.sort` shows `sorted_natural` within noise of `sorted`.

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md)
