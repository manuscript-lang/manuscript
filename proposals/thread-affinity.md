# Thread affinity for native handles

## Summary

- Problem: `promise(fn:)` runs its entry on any scheduler thread, but native handles in `ms-std-net` are `Rc`/`RefCell` (about 300 uses; also `ms-std-terminal`, `ms-std-archive`, `ms-std-json`, `ms-std-regex`). A handle that crosses threads races on its non-atomic counts and borrow flags. #3047: a `Listener` accepted inside a promise while the creator connects panics with `RefCell already borrowed` at `Network::own`.
- Existing protection is partial: `conn.rs` handles carry a `sched::Pin` so promises started from their thread stay on it. `Network`, clients, bodies and sockets have none.
- Change, stage 1 (this PR): `ms_std_net::bound::Bound<T>` records the creating thread and faults with a message naming the cause and `owned_promise` when another thread dereferences or clones it. `NetH`, `ConnH`, `ListenerH`, `DgramH`, `ClientH`, `BodyH` and `SocketH` wrap their `Rc` in it. A `repo-check` ratchet (`thread_affinity.rs`, `thread-affinity-allowed.txt`) forbids new `Rc`/`Weak`/`RefCell` lines in `crates/ms-std-*/src`, so the count can only shrink.
- Later stages: migrate `net.rs`, `conn.rs`, then `http/*` and `ws/*` to `Arc`, atomics or a lock where a handle really is shared, and delete `Bound` from a handle once it is thread-safe; do the same for the smaller crates; remove each ratchet entry as its file reaches zero.

## Alternatives considered

- Doing nothing: the race stays; the symptom is a panic or silent count corruption far from the cause.
- Pin every handle (re-route promises to the owning thread): a live `Network` or client on the main thread would pin every promise started there, including `serve` workers, and serialize them. Rejected for handles that are not tied to an open stream.
- Clippy `disallowed-types`: configuration is per crate directory and the workspace uses `Rc` legitimately in `ms-check`; a per-file ratchet gives the same ban with a staged migration and no new files per crate.
- Compile-time rejection of capturing a thread-bound handle in `promise(fn:)`: needs a language-level marker and checker support; deferred until the runtime guard shows which handles stay bound.

## Evidence

`tests/e2e/testdata/stdlib/net-thread-bound.ms` takes a `Network` into a promise while the main thread is busy; before the guard the promise uses the `Rc` from another thread, after it faults with `a native handle was used on a different thread`.
