[Wiki](../index.md) › [Runtime](index.md)

# Interrupted channel waits retire their queue entries

Verified: freeing a cancelled park token prevents stale delivery but leaves its ID in a source
lane's waiting list unless the wait registers cleanup. Repeated cancellations on an idle or full
channel therefore retain entries until a later wake. Register a private wait ticket before park,
remove only its own ID on exit, and release an empty list's capacity. Preserve other live waiters.

Apply when: parking on a source-managed queue or changing task-channel cancellation.
Evidence: [channel wait cleanup](../../stdlib/tasks.ms),
[deterministic sender/receiver checks](../../tests/e2e/testdata/stdlib/task-channel-wait-cancellation.ms),
and [retention finding #1505](https://github.com/manuscript-lang/manuscript/issues/1505).
Verify: acknowledged waits cancelled without sleeps retain no excess heap over an equally cancelled,
woken control; another live waiter still wakes. Keep samples within the small-block heap counter's
range, and report profile-specific cancellation allocations separately from queue storage.

---
Topics: [Concurrency and cancellation](../topics/concurrency-and-cancellation.md)
