[Wiki](../index.md) › [Language](index.md)

# Equality and hashing are source interfaces

Decision: the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces, and explicit implementations select domain identity. Custom equality requires an explicit consistent hash before the type becomes a key; structural hashing cannot silently use different fields. (The revamp kept reference semantics at the time; the value-semantics decision changes aliasing, not key identity.)

Apply when: changing equality operators, generic bounds, contract views, key lookup, or implementation visibility.
Evidence: [equality rules](../../documentation/core-language/types/equality-and-hashing.md), [source interfaces](../../stdlib/core.ms), and [compiled domain-key fixture](../../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: two keys with equal IDs and different labels compare equal and occupy one map entry; an equality override without a hash is rejected as a map key. Keep local implementation selection when forwarding generic arguments.
