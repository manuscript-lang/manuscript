[Wiki](../index.md) › [Language](index.md)

# Match is uniformly a value expression; indexing returns the element

Decision: when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form. A standalone match discards the same checked result. The earlier decision that brackets preserve `.at()`'s Optional result was reversed: `at` is removed, `[]` returns `T` and faults out of range, and `get(index, default: ...)` on List, String, and Bytes returns `T` or the default. `[]` also reads `Map[K, V]` (one probe; absent key faults `map key not found: <key>`) and `Bytes` (an `Int`, negative from the end); `m[k] = v` is `m.add(k, v)` and `m[k] += v` reads then adds. String has no `[]` because scalar position is not a constant-time offset, and Bytes cannot be assigned (decision: Chinmay, 2026-10-25, card "Both"). Generic specialization retains its existing meaning. The flow-sensitive bounds proof (#552) only narrowed the type while the read still faulted, so it was removed; reintroducing bounds-check elimination needs its own proof.

Apply when: changing matching, collection lookup, type application parsing, or examples migrating from other languages.
Evidence: [match values](../../documentation/core-language/control-flow/pattern-matching.md#arm-values), [list lookup](../../documentation/core-language/types/collections.md#lookup-and-updates), and [expression conformance](../../tests/e2e/testdata/accept/expression-conveniences.ms).
Verify: use `items.get(index, default: 0)` for absent indexes, keep `identity[Int]` specialization, and exercise enclosing returns, propagation, cleanup, and loop exits from match arms. Out-of-range `[]` faults with the index and length. An effects-only arm ending in a value-returning call needs an explicit `unit` when another arm produces Unit.

---
Topics: [Errors and results](../topics/errors-and-results.md)
