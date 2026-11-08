[Wiki](../index.md) › [Runtime](index.md)

# Native handles built on Rc are thread-bound and fault elsewhere

Decision (2026-11-08, #3047): `promise(fn:)` may run on any scheduler thread, so an `Rc`/`RefCell` handle used there races. `ms_std_net::bound::Bound` wraps the handle's `Rc` and faults naming the cause when another thread dereferences it; `owned_promise` keeps work on the creating thread. `make repo-check` bans new `Rc`, `Weak` or `RefCell` lines in `crates/ms-std-*/src` and ratchets the remaining ones in `crates/ms-repo-check/thread-affinity-allowed.txt`; lower an entry in the change that removes the use.

Apply when: adding a native handle, or moving one to `Arc`/atomics (then drop its `Bound`).
Evidence: `tests/e2e/testdata/stdlib/net-thread-bound.ms`; plan in `proposals/thread-affinity.md`.

Pinning a promise to the handle's thread (`sched::Pin`) is right for handles tied to an open stream, wrong for a `Network` or client: a live one on the main thread would pin `serve` workers there.
