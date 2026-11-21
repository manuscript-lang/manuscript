[Wiki](../index.md) › [Standard-library design](index.md)

# Pick the failure mode by cause, then the shape

Decision: absence is `Optional`, invalid external data is `Result`, a violated documented precondition faults. `[]` returns `T` and faults out of range; `get(index, default)` on List, String, and Bytes returns `T` or the default; `at()` is removed (#669).

Decision (Chinmay, 2026-11-16, reversing the earlier "a caller mistake faults everywhere" hardening rule): a bad value from the caller returns an `Error` (`EINVAL`) or `none`; a fault is for a true bug only, such as an index out of range, integer overflow, or reading a flag the schema never declared. A safe-to-write language should not crash because a size, count, radix or budget was wrong, and an agent sees a returned error at the call site where a crash shows up at run time. Use `EINVAL` for a bad argument in a function that already returns `Error`, and `none` where the function can already return `none`; do not change a signature to add a new error. Where a count has a natural meaning at zero (`take`, `drop`, `repeated`, `chunks`, `windows`, `cycle`, `split` caps, queue capacity, histogram observations, diff context), zero or below uses it: nothing, or an empty list. A selection with no answer (`combinations` of a size larger than the list, `percentile` outside 0 to 100, `bin_counts` below 1 bin, `correlation` of unequal lists) is an empty list or `none`.

The rule is written once in [Choosing a failure](../../documentation/core-language/errors/_index.md#choosing-a-failure-in-the-standard-library) (2026-11-17, after #4345 to #4362 and #4366 to #4370 flipped it within a day); `SeededRandom.weighted_choice` returns `none` for bad weights because it already returned `T?`. Shifts are total: a count of 64 or more shifts every bit out (`shift_left` and `shift_right_unsigned` give 0, `shift_right` gives 0 or -1 by sign); a negative count still faults because it is arithmetic nonsense, not data. `rate_limiter` and `BitSet.add` return `EINVAL` for a bad number (`BitSet.add` is now `Void!`: a silent drop would lose a member). Measured 2026-11-16: a 40-round 400000-add BitSet loop and a 40M-iteration shift loop run within noise of before.

`to_string_radix` returns `none` for a radix outside 2 through 36 (Chinmay, 2026-11-17); the common bases cannot fail, so use `to_string()`, `to_hex()` and `to_binary()`. Python has `bin`, `oct` and `hex` but no general base-N; the same split.

`Iterable` and `for` over it were removed (Chinmay, hardening week): `Deque`, `Queue` and `PriorityQueue` read by position with `get(index)` returning an optional, negative indexes from the end, like `Map.get(key)`. A plain `T` cannot be returned from a borrowed element in Manuscript source (only the native `List.get` lends), so the optional form is the one expressible spelling; walk with `for i in 0..q.length()`.

Apply when: designing any fallible read, lookup, or conversion.
Evidence: [Optional](../../src/stdlib/core/core.ms), [Result](../../src/stdlib/core/core.ms), commits f7a3f26a and 040f6321, [collection rules](../../documentation/core-language/types/collections.md).
Verify: out-of-range `[]` faults, `get_or(i, x)` returns `x`, and no `unwrap*` or `at` declaration remains (`ms search_symbol unwrap`).
