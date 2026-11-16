[Wiki](../index.md) › [Standard-library design](index.md)

# Pick the failure mode by cause, then the shape

Decision: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. `[]` returns `T` and faults out of range; `get(index, default)` on List, String, and Bytes returns `T` or the default; `at()` is removed (#669).

Hardening week (Chinmay): a caller mistake faults everywhere, not only in seeded generators; `random.sample`, `weighted_choice`, `secure_int` and `random_bytes` fault on a bad argument and still return an `Error` for an entropy failure. BigInt, fs and the rest follow module by module.

`Iterable` and `for` over it were removed (Chinmay, hardening week): `Deque`, `Queue` and `PriorityQueue` read by position with `get(index)` returning an optional, negative indexes from the end, like `Map.get(key)`. A plain `T` cannot be returned from a borrowed element in Manuscript source (only the native `List.get` lends), so the optional form is the one expressible spelling; walk with `for i in 0..q.length()`.

Apply when: designing any fallible read, lookup, or conversion.
Evidence: [Optional](../../stdlib/core/core.ms), [Result](../../stdlib/core/core.ms), commits f7a3f26a and 040f6321, [collection rules](../../documentation/core-language/types/collections.md).
Verify: out-of-range `[]` faults, `get(i, default: x)` returns `x`, and no `unwrap*` or `at` declaration remains (`ms search_symbol unwrap`).
