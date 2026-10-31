[Wiki](../index.md) › [Runtime](index.md)

# Result collection does not transfer a task channel's resource lifetime

Decision (Chinmay, 2026-10-26): closing a group closes every channel it handed out, including
retained or cloned handles after result collection. Preserve collection's bounded retention:
discarded channels must not remain owned by the group, and retained unread buffers release at close.
The private tracker weakly links channel leases; each lease owns its callback and retains its tracker.
Detach and take the callback before invoking it. Never retain a weak-listed lease: deferred object
drops reuse a zero-count object's count word for the pending list.

Apply when: changing task collection, channel lifetime, or group close.
Evidence: [resolved contract and design](../../proposals/task-channel-lifetime.md),
[called lifecycle checks](../../tests/e2e/testdata/stdlib/task-channel-lifetime.ms),
and [native lease regressions](../../crates/ms-rt/src/channel.rs).
Verify: retained channels drain before group close, then give Closed; unread payloads release at
close; last-handle drop removes tracking without another spawn; deferred drops and reentry stay valid.

---
Topics: [Cleanup and resources](../topics/cleanup-and-resources.md)
