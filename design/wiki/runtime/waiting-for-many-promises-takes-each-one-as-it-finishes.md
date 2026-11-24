[Wiki](../index.md) › [Runtime](index.md)

# Waiting for many promises takes each one as it finishes

Verified (2026-11-15, 4-core x86-64 sandbox, #3961): `wait_all` called `wait_any` after every wake, and each call copied the id list, scanned it, and put a token on every promise. With thieves finishing promises one event at a time that was a full pass per completion: 10,000 promises that each sleep 1 s took 1.9 s on 4 threads against 1.05 s on one. `wait_all` now adds the promises to a runtime wait group (`msrt_group_*`, same-thread promises only) that logs each finished tag once; a promise of another thread falls back to `wait_any`. Do not add a group to the public API (see [promises and pipes only](concurrency-is-promises-and-pipes-only.md)); it is internal to `wait_all`.

The same change fixed a hidden cost: `remove_pending` scanned the whole queue of unstarted promises whenever the id was already gone (taken by an idle thread), under the lock the thieves need. Starts now carry a `seq`, the queue is sorted by it, and the lookup is a front check or binary search. An experiment that only added the group made 100k tiny promises on 4 threads slower (50 to 150 ms) until this was fixed, and instruction counts under callgrind did not show it; the signature was 1,700 futex calls against 12 in `strace -c -f`.

Apply when: changing `wait_all`, `wait_first`, `msrt_promise_wait_any`, or the unstarted-promise queue in `sched.rs`.
Evidence: [`promise.ms`](../../../src/stdlib/concurrency/promise.ms), [`promise.rs`](../../crates/ms-rt/src/promise.rs), [`promise-semantics.ms`](../../../tests/conformance/fixtures/e2e/stdlib/promise-semantics.ms).
Verify: ten thousand promises sleeping 1 s, `wait_all` on `MS_THREADS=4` finishes in about 1.06 s; compare 100k small promises at 1 and 4 threads with `strace -c -f` and expect single-digit futex calls.
