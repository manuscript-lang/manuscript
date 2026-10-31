[Wiki](../index.md) › [Standard-library design](index.md)

# Pick the failure mode by cause, then the shape

Decision: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. `[]` returns `T` and faults out of range; `get(index, default)` on List, String, and Bytes returns `T` or the default; `at()` is removed (#669). `Optional.get(default)` and `Result.get(default)` replace `unwrap`/`unwrap_or` (a missing default on none/error still faults), `get_or_else(create)` on Optional and Result replaces `unwrap_or_else`; `or_else(create)` returns the same wrapper on both (lazy alternative) and `Result.map_error` transforms the error, and `Result.err()` replaces `unwrap_error`. Eager `get(default)` and lazy `get_or_else(create)` are the only pair; `or_else` never unwraps.

Apply when: designing any fallible read, lookup, or conversion.
Evidence: [Optional](../../stdlib/core.ms), [Result](../../stdlib/core.ms), commits f7a3f26a and 040f6321, [collection rules](../../documentation/core-language/types/collections.md).
Verify: out-of-range `[]` faults, `get(i, default: x)` returns `x`, and no `unwrap*` or `at` declaration remains (`ms search_symbol unwrap`).

---
Topics: [Errors and results](../topics/errors-and-results.md)
