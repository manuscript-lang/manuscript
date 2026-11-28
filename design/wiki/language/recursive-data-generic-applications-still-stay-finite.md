[Wiki](../index.md) › [Language](index.md)

# Recursive data; generic applications still stay finite

Decision: direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the inline-layout restriction. Preserve complete initialization and cycle-safe structural equality. Recursive shapes must not automatically derive Hashable: structural hashing has no cycle guard, while explicit domain identity implementations remain available.

Apply when: changing recursive data, automatic equality/hashing, or generic regularity checks.
Evidence: [recursive data rules](../../../documentation/core-language/types/named-types.md#recursive-data), declaration cycle pass, and [recursive data fixture](../../../tests/lang/misc/recursive-types.ms).
Verify: direct and mutual trees execute; cyclic equality terminates; uninitialized self-references and automatic recursive hashing fail. Finite nested generic applications pass; expanding cycles through fields, callbacks, or interfaces fail.

Verified (2026-11-28): `msrt_eq_enter` and `msrt_eq_leave` had no callers. `msstd_value_equals` (`src/runtime/std/shape_equal.c`) stops at depth 256 and returns false, so a cycle compares unequal and does not fault. The unused guard and the per-task `eq_pairs` list were removed. Treating a cycle as equal, or faulting past a depth, would be a behavior change.
