[Wiki](../index.md) › [Language](index.md)

# Equality and hashing are source interfaces

Decision: the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces, and explicit implementations select domain identity. Custom equality requires an explicit consistent hash before the type becomes a key; structural hashing cannot silently use different fields. (The revamp kept reference semantics at the time; the value-semantics decision changes aliasing, not key identity.)

Decision (user, 2026-10-26): `Equal.equals` and `Comparable.compare` take `other: Self`, so an implementation writes its own type instead of matching an `Equal` argument. `Self` is an interface-only implicit variable allowed as a whole parameter or result type (`Clonable.clone` returns `Self`); calls substitute the receiver (the interface itself for interface values, the bounded variable for `T: Equal`). The vtable entry unboxes a `Self` argument and answers `False` (`equals`) or faults (`compare`) for another dynamic type, so direct calls and `==` never box. In an `impl Type:` block (inherent methods), `Self` is the receiver type and is allowed anywhere in a signature or body (user, 2026-10-26).

Apply when: changing equality operators, generic bounds, contract views, key lookup, or implementation visibility.
Evidence: [equality rules](../../documentation/core-language/types/equality-and-hashing.md), [source interfaces](../../stdlib/core.ms), and [compiled domain-key fixture](../../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: two keys with equal IDs and different labels compare equal and occupy one map entry; an equality override without a hash is rejected as a map key. Keep local implementation selection when forwarding generic arguments.

Decision: all values may be passed freely, and closures have ordinary captures. Concurrency and shared-state guards were removed pending a ground-up redesign. (Under value semantics, closure capture is by borrow or move; see the ownership notes.)

---
Topics: [Types and interfaces](../topics/types-and-interfaces.md)
