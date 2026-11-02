[Wiki](../index.md) › [Standard-library design](index.md)

# Go collections parity: existing ops, small in-place ones, no lazy iterator adapters

Decision (Chinmay: match capability, not Go's API): List gained `retain`, `compact`/`compact_by`, `rotate`, `sorted_by_key`, `is_sorted`/`is_sorted_by` and `repeated`; Map and Set gained `remove_if`; Deque gained `rotate` (the ring). All are written in Manuscript in [collections.ms](../../stdlib/collections/collections.ms) over `swap`/`splice`, so they move elements and need no `Clonable` unless they copy. Already covered, so no new API: `insert`, `splice` (delete_range), `slice` (clone_range), `reserve` (grow), `==` on lists and maps (equal), `merge`, `keys().sorted()` (keys_sorted), `Deque` (container/list). Not built: lazy `map/filter/zip` iterator adapters, because `Iterator.next` lends a borrow that is valid only until the loop body ends, so an adapter cannot hold or return owned results without a new ownership design; use eager List operations or a `for` loop.

Apply when: asked for a Go `slices`/`maps`/`container` equivalent, or for lazy iterator combinators.
Evidence: [list-reshape fixture](../../tests/e2e/testdata/stdlib/list-reshape.ms), [Iterator](../../stdlib/core.ms).
Verify: `ms test tests/e2e/testdata/stdlib/list-reshape.ms`.
