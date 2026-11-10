[Wiki](../index.md) › [Runtime](index.md)

# Native transformations need output implementation evidence

Verified: a generic native receiver's type name does not carry lexical Equal/Hashable selection. `Set.map` and `Map.map_keys` deduplicate output elements/keys, whose module scope can differ from the input element/key scope. Resolve both the receiver scope and the mapped result scope, including explicit specialization and bound methods, and use output evidence for deduplication. Keep Map/Set callback membership snapshots at the native invocation boundary.

Borrowed-key updates must resolve the map's stored creator descriptor before hashing or copying a key, just as consuming updates do. This also applies to an empty stamped map: using caller evidence can insert an entry that ordinary lookup cannot reach. Runtime regression coverage lives in `map::tests::borrowed_adds_keep_creator_identity_and_release_owned_values`.

Binary Set operations must probe each operand's index with that operand's stored descriptor, while derived outputs keep the left creator. Even identical equality rules can have different valid hashes in two modules; using the left hash against the right index loses shared members. `projects/set_operand_hash` tests algebra, relations, bound/generic calls and independent copies without changing the equality rule.


Apply when: adding native transformations with output bounds or changing receiver specialization.
Evidence: [cross-module output evidence](../../tests/e2e/testdata/projects/core_parity/conformance_test.ms), [callback mutation conformance](../../tests/e2e/testdata/stdlib/core-parity.ms).
Verify: a generic input forwarded from another module still maps to a set deduplicated by the defining output module's equality; two modules can select different implementations for the same type.
