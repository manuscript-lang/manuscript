[Wiki](../index.md) › [Language](index.md)

# Recursive data; generic applications still stay finite

Decision: direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the inline-layout restriction. Preserve complete initialization and cycle-safe structural equality. Recursive shapes must not automatically derive Hashable: structural hashing has no cycle guard, while explicit domain identity implementations remain available. Open: the original decision also required reference aliasing and shallow cloning for recursive nodes; reconcile that with value semantics (indirection, `.copy()`) in the ownership notes before relying on it.

Verified: declaration dependency cycles distinguish finite nesting such as `Box[Box[Int]]` from expanding generic recursion. Track generic substitutions around declaration cycles rather than recursively expanding storage layouts. The finite-application rule includes references in generic arguments, functions, and interface operations; indirect storage cannot hide an expanding type family. Collection identities are not user declaration cycles. Keep active cycle detection separate from completed equality/hashing results, so shared acyclic shapes do not trigger exponential property checking.

Apply when: changing recursive data, automatic equality/hashing, or generic regularity checks.
Evidence: [recursive data rules](../../documentation/core-language/types/records.md#recursive-data), [declaration cycle pass](../../crates/ms-check/src/recursion.rs), and [recursive data fixture](../../tests/e2e/testdata/accept/recursive-types.ms).
Verify: direct and mutual trees execute; cyclic equality terminates; uninitialized self-references and automatic recursive hashing fail. Finite nested generic applications pass; expanding cycles through fields, callbacks, or interfaces fail.

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md)
