# Promise options: timeout and cancel signal at construction

Status: **implemented** in PR on `claude/project-thread-iu5rua` (the constructor is `cancel_switch()`, since opaque types cannot be built with `Cancel()`). Earlier status: proposal (2026-11-03), checked against main `d88b9299`. Snippets are unchecked (they need the new API). Direction (Chinmay, 2026-11-03): move the `wait` timeout to the promise constructor, add an options field holding the timeout and a cancel signal.

## Summary

Decision (Chinmay, 2026-11-03): approved; keep `signal()` (owner `Cancel`, copyable `Signal`).

- Problem: a timeout belongs to the work, but today it is an argument of one `wait`, so it does not bound work nobody waits on, and nothing outside the promise can cancel it except dropping it.
- Change: `promise(fn:, options:)` takes `PromiseOptions { timeout, cancel }`; `wait` loses `timeout`; a new `Cancel` owner and `Signal` handles cancel many promises at once.
- Decision requested: the three open questions at the end.

## Problem

```manuscript
job := promise(fn: crunch(data))
// 5 s limit exists only if this exact wait runs; done() or a drop-free exit never enforces it
result := try job.wait(timeout: seconds(5))
```

- The limit starts when `wait` is called, not when work starts (`msrt_promise_wait`, `crates/ms-rt/src/promise.rs:909`).
- A promise that is polled with `done()`, or whose waiter is itself waiting, has no deadline.
- Cancel is only reachable by dropping the promise or the host-level flag (signals, shutdown). A caller cannot say "stop all of these when the user hits Cancel".
- About 45 `wait(timeout:)` call sites exist: stdlib (`net/http.ms`, `net/net.ms`, `io/io.ms`, `os/process.ms`), tests, docs, cheat sheet.

## Design

```manuscript
export type PromiseOptions:
    timeout: Duration? = none
    cancel: Signal? = none

export fn promise[U](entry: fn() U!, options: PromiseOptions = PromiseOptions()) Promise[U]

export type Cancel                       // the owner: a resource, freed at scope end
impl Cancel:
    fn signal() Signal                   // a copyable handle (generation + slot index)
    fn cancel() Unit                     // idempotent; never waits
export type Signal                       // plain data; `.clone()` copies it
impl Signal:
    fn cancelled() Bool                  // for CPU loops that never wait

stop := cancel_switch()          // opaque types are made by a function, like `pipe`
a := promise(fn: crunch(data), options: PromiseOptions(timeout: seconds(5), cancel: stop.signal()))
stop.cancel()                          // a ends: wait reports Cancelled
```

**Timeout**
- The deadline is fixed at construction (`now + timeout`) and enforced by the runtime without a waiter: at the deadline the work is cancelled and the promise ends with `Timeout`. `wait` then reports `Timeout`, even if called later.
- A negative timeout is no time at all (as `nanos` does today), not "none".
- A promise that finishes before the deadline keeps its result; a tie goes to the result.
- Cost: a `deadline` column in the promise table (sentinel for none) and one entry in the existing timer heap only for limited promises; unlimited promises pay nothing.

**Cancel**
- A signal is a slot id in a flat table with a generation, like promise ids. No refcount: the `Cancel` owner owns the slot; a `Signal` is a copyable id.
- Construction with a signal registers the promise with the slot (a small index list per slot). `cancel()` calls the existing `request_cancel(id)` for each registered promise, on its own thread via `sched::post`, the same path as dropping or timing out.
- A signal already cancelled at construction: the work never starts and ends `Cancelled`.
- Dropping the owner does not fire; it unregisters the promises and frees the slot. A stale signal reads as not cancelled. (Firing on drop would cancel work by a scope exit the caller did not intend; use `cancel()` explicitly.)
- First of timeout, signal, drop wins; the outcome code is the first cause.

**Propagation and cleanup**
- Cancellation is delivered at the next wait, as today (`documentation/core-language/concurrency/promises.md`); cleanups run as on any other exit. A loop that never waits can poll `signal.cancelled()`.
- Cancelling a promise cancels the promises it is waiting on, since the cancelled wait unwinds and drops them (existing behavior). Nothing new is linked implicitly: a child promise made inside the work with the parent's `Signal` needs it passed in (captured clone).
- I/O: an I/O promise cancels through the same `on_drop` retry with `WAIT_CANCELLED`, so sockets and files release exactly as when dropped.
- `wait_all` / `wait_first` still cancel the rest on the first error or result; no change.
- Task groups no longer exist after the concurrency redesign (`concurrency-redesign.md`); a `Cancel` plays the group-scope role when a caller wants one switch.

**Migration**
- `wait(timeout:)` is removed in the same PR (pre-release; no deprecation shim). Each caller moves the limit to the constructor.
- Promises made by the stdlib (`read`, `fetch`, `connect`, `sleep`, `exec`, `accept`) are not made by `promise(fn:)`. For these, add one consuming method `fn with(options: PromiseOptions) Promise[T]` on `Promise[T]` that applies a deadline and signal to an existing promise, so `read(p).with(options: PromiseOptions(timeout: seconds(5))).wait()` replaces `read(p).wait(timeout: seconds(5))` mechanically. Existing `timeout:` parameters on `connect`, `fetch`, `accept` stay.
- One Rust change per call site is not needed: tests and docs are rewritten by a script over `wait(timeout: X)` -> `.with(options: PromiseOptions(timeout: X)).wait()`, then the `promise(fn:)` sites are moved by hand.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/promise.ms` | `PromiseOptions`, `Cancel`, `Signal`, `with`; drop `timeout` from `wait` | e2e `promise-semantics.ms`: timeout without waiter, cancel before start, cancel mid-wait, source drop |
| `crates/ms-rt/src/promise.rs` | `deadline` column, timer entry, signal table, `msrt_promise_set_limits`, `msrt_cancel_*` | Rust unit tests next to `a_timeout_cancels_the_work_and_drop_joins_it` |
| `stdlib/internal/promises.ms` | new extern declarations | `ms check` stdlib |
| `stdlib/net`, `io`, `os/process.ms`, tests, docs, cheat sheet | migrate ~45 `wait(timeout:)` sites | existing suites, `make verify` |
| Wiki (runtime) | record deadline-at-construction and signal-slot rules | n/a |

## Alternatives

1. **Do nothing.** Cheapest; keeps timeouts that only bite at a wait, and no group-wide cancel.
2. **Keep `wait(timeout:)` and add `options` for cancel only.** Two places to say a limit, and the wait-time deadline stays unenforced without a waiter. Rejected.
3. **Refcounted `Shared` token.** Rejected by the owner (no refcount, no `Shared`); a source with copyable ids avoids it.
4. **Cancel by passing a `Promise` as parent.** No new type, but it cancels one thing and ties lifetimes together. Rejected.

## Stages

1. Runtime deadline at construction plus `PromiseOptions(timeout:)`, `with`, and migration of all `wait(timeout:)` sites. Check: `make verify`.
2. `Cancel`, runtime signal table, docs and cheat sheet. Check: new e2e fixtures, full CI matrix (Windows timer and cancel paths).

Stage 1 and 2 ship in one PR unless the runtime change conflicts with the concurrent threads below.

## Coordination

Touches `crates/ms-rt/src/promise.rs` and the promise slot table, as do "Bug bash concurrency, net and streams" and "Support millions of growable tasks". The `deadline` column and signal table must follow whatever layout growable tasks settles on; agree before implementing.

## Open questions

1. **Should `timeout` still stay available on `wait` for one-off use?** Recommend no: one place only.
2. **Should every stdlib promise constructor take `options:` instead of `with`?** Recommend `with` now, per-constructor later where it earns its place.
3. **Should dropping a `Cancel` owner cancel its promises?** Recommend no (explicit `cancel()` only).
