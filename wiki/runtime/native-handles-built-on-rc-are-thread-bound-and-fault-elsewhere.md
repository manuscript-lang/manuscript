[Wiki](../index.md) › [Runtime](index.md)

# Native handles built on Rc are thread-bound and fault elsewhere

Decision (2026-11-08, #3047): `promise(fn:)` may run on any scheduler thread, so an `Rc`/`RefCell` handle used there races. `ms_std_net::bound::Bound` wraps the handle's `Rc` and faults naming the cause when another thread dereferences it; `owned_promise` keeps work on the creating thread. `make repo-check` bans new `Rc`, `Weak` or `RefCell` lines in `crates/ms-std-*/src` and ratchets the remaining ones in `crates/ms-repo-check/thread-affinity-allowed.txt`; lower an entry in the change that removes the use.

Apply when: adding a native handle, or moving one to `Arc`/atomics (then drop its `Bound`).
Evidence: `tests/e2e/testdata/stdlib/net-thread-bound.ms`; plan in `proposals/thread-affinity.md`.

Pinning a promise to the handle's thread (`sched::Pin`) is right for handles tied to an open stream, wrong for a `Network` or client: a live one on the main thread would pin `serve` workers there.

`Network` is the exception and is shared: a promise that captures a network is ordinary (stage 1 bound it by mistake and `net.ms` "resolve returns typed DNS records" failed whenever the promise landed on another thread). Its resources register per thread, so closing it from another thread closes only its children and the resources opened on the closing thread.

Why not `Arc` for the rest (tried 2026-11-08): `Network` registers `Client` and `ResponseBody`, the HTTP stack is per-thread by design (reactor, server, sessions), and a socket shared by threads needs an atomic closed/busy/release handshake. Bind the handle; migrate a type only when a real program must share it across threads. A full `make e2e` (needs `target/debug/ms` built) is the check for a new bound handle: a handle the stdlib itself moves into a promise shows up there.
