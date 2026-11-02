[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Empty Set relations need no membership probes

Verified: `Set.is_disjoint_from` used to scan every left member when the right set was empty. `find_slot` already returns before hashing an empty collection, so returning true before traversal preserves hash/equality callback behavior. Keep the existing traversal for nonempty operands; choosing the smaller side can reorder user operations.

Apply when: optimizing Set predicates without changing user-defined Hashable/Equal effects.
Evidence: [query and callback test](../../crates/ms-rt/src/map.rs), [paired Set and Map controls](../../bench/perf/set-empty-relations/README.md).
Verify: `empty_set_relations_do_not_hash_members`, `set_relations_stop_at_first_decisive_key`, empty and nonempty paired native workloads; retain tiny-input and unrelated Map controls.
