[Wiki](../index.md) › [Language](index.md)

# Match is uniformly a value expression; indexing returns the element

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The earlier decision that brackets preserve `.at()`'s Optional result was reversed: `at` is removed, `[]` returns `T` and faults out of range, and `get(index, default: ...)` on List, String, and Bytes returns `T` or the default.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../../documentation/core-language/types/collections.md#lookup-and-updates), and [expression conformance](../../tests/e2e/testdata/accept/expression-conveniences.ms).
Verify: use `items.get(index, default: 0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. Out-of-range `[]` faults with the index and length.
