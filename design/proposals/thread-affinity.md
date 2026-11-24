# Thread affinity for native handles

## Summary

- Problem: `promise(fn:)` runs its entry on any scheduler thread, but native handles in `ms-std-net` are `Rc`/`RefCell` (about 300 uses; also `ms-std-terminal`, `ms-std-archive`, `ms-std-json`, `ms-std-regex`). A handle that crosses threads races on its non-atomic counts and borrow flags. #3047: a `Listener` accepted inside a promise while the creator connects panics with `RefCell already borrowed` at `Network::own`.
- Existing protection is partial: `conn.rs` handles carry a `sched::Pin` so promises started from their thread stay on it. `Network`, clients, bodies and sockets have none.
- Change, stage 1 (this PR): `ms_std_net::bound::Bound<T>` records the creating thread and faults with a message naming the cause and `owned_promise` when another thread dereferences or clones it. `NetH`, `ConnH`, `ListenerH`, `DgramH`, `ClientH`, `BodyH` and `SocketH` wrap their `Rc` in it. A `repo-check` ratchet (`thread_affinity.rs`, `thread-affinity-allowed.txt`) forbids new `Rc`/`Weak`/`RefCell` lines in `crates/ms-std-*/src`, so the count can only shrink.
- Stage 2: `Network` (and `Policy`) become genuinely shared (`Arc`, an atomic closed flag, a locked child list), because a network captured by a promise is ordinary use (`net.ms`, "resolve returns typed DNS records", which stage 1 broke when the promise landed on another thread). Resources a network opened (`Rc` handles) register in the opening thread's registry and are closed with the network on that thread; on other threads they see `is_closed` at their next operation. `HeadersH`, `ExchH` and `WorkerH` are bound too, so every `Rc`-holding handle except `ServingH` (borrowed read-only by workers) is thread-bound.
- Not done, deliberately: `Arc` for `Connection`, `Listener`, `Client`, `ResponseBody`, `Server`. The HTTP reactor, `Conn`, `Server` and `Session` are per-thread by design, and a socket shared by threads needs an atomic closed/busy/release handshake. That is a redesign for a use nobody has asked for; `owned_promise` keeps socket work on one thread, and the guard names the mistake.

## Alternatives considered

- Doing nothing: the race stays; the symptom is a panic or silent count corruption far from the cause.
- Pin every handle (re-route promises to the owning thread): a live `Network` or client on the main thread would pin every promise started there, including `serve` workers, and serialize them. Rejected for handles that are not tied to an open stream.
- Clippy `disallowed-types`: configuration is per crate directory and the workspace uses `Rc` legitimately in `ms-check`; a per-file ratchet gives the same ban with a staged migration and no new files per crate.
- Compile-time rejection of capturing a thread-bound handle in `promise(fn:)`: needs a language-level marker and checker support; deferred until the runtime guard shows which handles stay bound.

## Evidence

`tests/e2e/testdata/stdlib/net-thread-bound.ms` (main thread kept busy so another thread takes the promise): `HttpHeaders` captured by a promise faults with `a native handle was used on a different thread`; a `Network` captured by a promise keeps working.
