[Wiki](../index.md) › [Runtime](index.md)

# Native transformations need output implementation evidence

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. `Set.map` and `Map.map_keys` deduplicate output elements/keys, whose module scope can differ from the input element/key scope. Resolve both the receiver scope and the mapped result scope, including explicit specialization and bound methods, and use output evidence for deduplication. Keep Map/Set callback membership snapshots at the native invocation boundary.

Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: [cross-module output evidence](../../tests/e2e/testdata/projects/core_parity/conformance_test.ms), [callback mutation conformance](../../tests/e2e/testdata/stdlib/core-parity.ms).
Verify: a generic input forwarded from another module still maps to a set deduplicated by the defining output module's equality; two modules can select different implementations for the same type. A bound specialized method retains its defining module, and callback removals or clearing do not alter the traversal's original membership.
