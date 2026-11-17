[Wiki](../index.md) › [Standard-library design](index.md)

# Pick the failure mode by cause, then the shape

Decision: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. `[]` returns `T` and faults out of range; `get(index, default)` on List, String, and Bytes returns `T` or the default; `at()` is removed (#669).

Decision (Chinmay, 2026-11-16, reversing the earlier "a caller mistake faults everywhere" hardening rule): a bad value from the caller returns an `Error` (`EINVAL`) or `none`; a fault is for a true bug only, such as an index out of range, integer overflow, or reading a flag the schema never declared. A safe-to-write language should not crash because a size, count, radix or budget was wrong, and an agent sees a returned error at the call site where a crash shows up at run time. Use `EINVAL` for a bad argument in a function that already returns `Error`, and `none` where the function can already return `none`; do not change a signature to add a new error. Unsigned integer types for counts were considered and dropped: callers compute counts from `length()`, which is signed, so the conversion and the underflow fault land on the caller.

`Iterable` and `for` over it were removed (Chinmay, hardening week): `Deque`, `Queue` and `PriorityQueue` read by position with `get(index)` returning an optional, negative indexes from the end, like `Map.get(key)`. A plain `T` cannot be returned from a borrowed element in Manuscript source (only the native `List.get` lends), so the optional form is the one expressible spelling; walk with `for i in 0..q.length()`.

Apply when: designing any fallible read, lookup, or conversion.
Evidence: [Optional](../../stdlib/core/core.ms), [Result](../../stdlib/core/core.ms), commits f7a3f26a and 040f6321, [collection rules](../../documentation/core-language/types/collections.md).
Verify: out-of-range `[]` faults, `get(i, default: x)` returns `x`, and no `unwrap*` or `at` declaration remains (`ms search_symbol unwrap`).
