[Wiki](../index.md) › [Language](index.md)

# Recursive data; generic applications still stay finite

Decision: direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the inline-layout restriction. Preserve complete initialization and cycle-safe structural equality. Recursive shapes must not automatically derive Hashable: structural hashing has no cycle guard, while explicit domain identity implementations remain available.

Apply when: changing recursive data, automatic equality/hashing, or generic regularity checks.
Evidence: [recursive data rules](../../documentation/core-language/types/records.md#recursive-data), [declaration cycle pass](../../crates/ms-check/src/recursion.rs), and [recursive data fixture](../../tests/e2e/testdata/accept/recursive-types.ms).
Verify: direct and mutual trees execute; cyclic equality terminates; uninitialized self-references and automatic recursive hashing fail. Finite nested generic applications pass; expanding cycles through fields, callbacks, or interfaces fail.
