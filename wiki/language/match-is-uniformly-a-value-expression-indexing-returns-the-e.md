[Wiki](../index.md) › [Language](index.md)

# Match is uniformly a value expression; indexing returns the element

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The earlier decision that brackets preserve `.at()`'s Optional result was reversed: `at` is removed, `[]` returns `T` and faults out of range, and `get(index, default: ...)` on List, String, and Bytes returns `T` or the default.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../../documentation/core-language/types/collections.md#lookup-and-updates), and [expression conformance](../../tests/conformance/fixtures/e2e/accept/expression-conveniences.ms).
Verify: use `items.get(index, default: 0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. Out-of-range `[]` faults with the index and length.

Missing arm values are diagnosed at the arm with the required result type. The type can come from an enclosing annotation rather than another arm, so an inferred-arm position is not always available (#3491). Binding a match to an ignored name still uses its result; it does not make the match a standalone statement. Check both expected and inferred result types and compile the diagnostic's suggested repair (`crates/ms-check/tests/match_patterns.rs`).
