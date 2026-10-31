[Wiki](../index.md) › [Language](index.md)

# Mutable data uses explicit copying

Decision (user, under reference semantics): ordinary record fields and collections are mutable. The user rejected immutable replacement APIs and instance freezing in favor of an explicit duplicate operation (`.clone()`). Preserve `let`/`var` binding rules independently of object mutation. Do not manufacture copies of sockets, files, locks, or other native service handles.

Superseded in part: under value semantics `let` is deeply immutable, aliasing is gone, `.clone()` is deep (the `.copy()` rename was dropped; `Clonable` landed in #1134), and resources are move-only and never copied. The statements that aliases observe mutation, that a clone's nested references stay shared, and that a cloned record may retain a handle reference no longer hold. Treat [ownership notes](../../crates/ms-check/OWNERSHIP.md) as authoritative; fixtures tagged `aliasing` in the conformance corpus are excluded for this reason.

Apply when: changing fields, collection updates, copies, or equality.
Evidence: [record contract](../../documentation/core-language/types/records.md#mutation-and-cloning); [collection contract](../../documentation/core-language/types/collections.md#mutation-and-copies); [mutation fixture](../../tests/e2e/testdata/accept/mutation.ms); [ownership notes](../../crates/ms-check/OWNERSHIP.md).
Verify: the counter's Unit-returning method updates `self.val`; a `.copy()` is independent of its source; copying a native resource is rejected. Do not restore removed sharing bounds.

---
Topics: [Ownership and value semantics](../topics/ownership-and-values.md)
