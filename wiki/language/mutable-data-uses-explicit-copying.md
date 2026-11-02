[Wiki](../index.md) › [Language](index.md)

# Mutable data uses explicit copying

Decision (user, under reference semantics): ordinary record fields and collections are mutable. The user rejected immutable replacement APIs and instance freezing in favor of an explicit duplicate operation (`.clone()`). Preserve `let`/`var` binding rules independently of object mutation. Do not manufacture copies of sockets, files, locks, or other native service handles.

Apply when: changing fields, collection updates, copies, or equality.
Evidence: [record contract](../../documentation/core-language/types/records.md#mutation-and-cloning); [collection contract](../../documentation/core-language/types/collections.md#mutation-and-copies); [mutation fixture](../../tests/e2e/testdata/accept/mutation.ms); [ownership notes](../../crates/ms-check/OWNERSHIP.md).
Verify: the counter's Unit-returning method updates `self.val`; a `.copy()` is independent of its source; copying a native resource is rejected. Do not restore removed sharing bounds.
