# Channels as the base for shared state: delete `Shared`, `lock` and the guard

## Summary

- Direction (Chinmay, 2026-10-30): "there's no reason for shared to be the base of the language"; get rid of `Shared` altogether.
- Today the user-facing `Shared[T]` + `lock` + `SharedGuard[T]` sits under the task channels (`Lane` is a `Shared`), the task result slot, the registries, the logger and the router. It needs three compiler special cases (#1422) and a wait queue.
- Verified: the runtime's refcounted object (`Obj`, `KIND_SHARED`) is a separate, legitimate base: closures, native handles (`NativeFile`, `NativeLink`) and the builders use it. Only the language-level generic box and its lock are the problem.
- Proposed base: a native **channel** handle. One runtime object carries values between holders, parks and wakes tasks, and is closed by either end. Everything that shares state today becomes a channel, a one-shot channel (result slot), or runtime-owned state next to an existing native handle. The user-facing story is Go's: share by communicating.
- Cost: one generic native channel in `ms-rt` (about 300-500 lines, sized against `pipe.rs` at 434 lines) plus lowering for its generic operations; rewrite of `tasks.ms`, `processes.ms`, `workers.ms`, `log.ms`, `router.ms`; deletion of about 800 lines of guard, wait-queue and special-case code and about 50 test files' worth of `lock` use.
- Decision requested: approve channels as the base, and the logger's error behavior (open question 1).

## Status

Proposal, 2026-10-30, checked against `origin/main` at `69d78f65`. Supersedes `retire-shared.md`, `shared-guard-consuming-close.md` and `lock-api.md`, whose skeptic reviews found: guards are held across parking calls in the library, a native lane costs 600-900 Rust lines if done naively, and a guard cannot be written in plain Manuscript (a generic `T` has no `clone`, fields cannot move). A local POC that made `Shared` a plain record produced 24 compile errors in `tasks.ms` (15), `processes.ms` (4), `router.ms` (4) and `log.ms` (1): every site where two holders need one mutable value. Nothing implemented.

**Skeptic review (2026-10-30): do not build as written.** The channel core (task lanes, result slot) is sound; deleting `Shared` entirely is not supported. Findings:
- Router `TestState` (`router.ms:456-590`) is a synchronous read-modify-write record inside non-`var` `HttpExchange` methods; a channel gives no read-your-own-write, so it needs a runtime-owned record, which is `Shared` again.
- Logger: `tests/e2e/testdata/stdlib/log.ms:150-166, 210-243` require immediate per-call `Closed`/`FileSystem` errors. Deferred errors break that contract; a per-call reply channel costs a task switch per record. A writer task runs only when some task waits, so plain `main` output reorders against direct stdout writes, and nothing owns the writer's lifetime.
- Size: `pipe.rs` is a global integer-id table, not a refcounted `Obj`, and holds bytes. A descriptor-carrying generic channel with hand-lowered ops (`native.rs`) is 600-900 Rust lines, the figure this proposal wrongly dismissed.
- Cancellation: a cancelled parked `send` leaves a stale waiter, and a moved-in value has no owner on unwind. Required API: cancellable park-until-room, then an infallible push (as `wait_for_room` plus `send` do now).
- Registries: `ChannelGroup` already closes handed-out channels, so group close needs no `Entry.channel`. The runtime table must be pointer-erased.
- Scope: about 47 conformance and 19 e2e files plus `shared-lock-*` fixtures and six doc pages use `Shared`/`lock`; removal is a user-visible language break that needs the owner's call.
- Net: complexity moves into Rust, and the logger and router keep `Shared`, so the claimed deletion does not happen.

Narrowed recommendation: build only stages 1-2 (task channels and result slot on a native channel, split park/push API, re-sized at 600-900 lines, with the stated go/no-go) and keep `Shared`/`lock` for logger, router test state and inbox until each has a sound replacement.

## Problem

- Verified: `Lane[T]` in `tasks.ms` is a record behind a `Shared` that sender and receiver both lock; `claim_room`, `send`, `receive`, `WaitTicket` and `close_end` are lock choreography around a queue and wait tokens.
- Verified: `Task.values`, `TaskGroup.tasks`, `Worker.ended`, `WorkerGroup.workers`, `Inbox` and the process registry are shared boxes written by one party and read by another.
- Verified: most library locks do not protect a multi-step invariant across a wait; they exist because closures capture by move, so two holders can only meet in a shared box. The sites that hold across blocking calls are `log.ms` `send`/`flush` (serializes transport writes), `workers.ms` `Worker.wait` and `processes.ms` `ProcessGroup.close` (idempotent join).
- Verified: top-level functions cannot move into a mixed native/source stdlib module, so the `lock(box)` function shape also blocks merging `shared.ms` and `sync.ms`.
- Non-goals: cross-thread shared memory; changing the builders (`StringBuilder` etc. share a runtime box and stay), closures or native handles; the channel user API.

## Design

Rule: sharing between tasks goes through a runtime-owned object with a defined protocol, never through a user-visible mutable box.

- **Native channel.** One refcounted runtime object per direction: a bounded queue of values of one type, closed flags for sender and receiver, and wait tokens for parked tasks. Operations `send` (parks while full), `receive` (parks while empty, `none` once closed and drained), `close_sender`, `close_receiver`, `length`. Values move in and out; elements are dropped by the type descriptor on `clear` and on last release. It generalizes `pipe.rs` (whole messages, bounded at 16, park on tokens) from encoded bytes to descriptor-driven values within one isolate.
- **Task channels.** `TaskTransport` becomes two native channels; `Lane`, `WaitTicket`, `claim_room`, `close_end` and every `lock` in the send/receive path are deleted. The `Channel` and `Transport` APIs do not change.
- **Task result.** A one-shot channel of capacity 1: the task sends its result, `result()` receives it. `collect`'s "already taken" case is a receive on a drained channel.
- **Group and worker registries.** The scope already tracks tasks by handle (`msrt_scope_spawn/join`); the entry table moves next to it in the runtime (handle, result channel, group end), so `Task` needs no shared registry to `forget` from. Workers keep their native pipe and gain a runtime outcome slot.
- **Process inbox and registry.** Inbox state (pending bytes, finished, result, closed) lives in the native link record that `msstd_process_ipc_*` already owns.
- **Logger.** Children hold clones of one request channel end; a writer task owns the transport and serializes writes. Write errors are reported by `flush()` and `close()` (open question 1).
- **Router.** The route table is an immutable value captured per handler. Test and tap state become a channel the harness drains (`snapshot` receives pending events).
- **Delete.** `shared.ms`, `sync.ms`, `Shared`, `share`, `lock`, `SharedGuard`, `Ticket`, `take/put/locked/id`, `sharedbuilder.rs`'s `shared_method`, `guard_held`, `copy_if`, the `close.rs` guard skip, `constfaults.rs` lock tracking and `check_shared_use`, the box wait queue (`msrt_waitq_*`), the lock fixtures and docs. User code that needed shared mutable state uses a channel or an owner task.

```manuscript
# before, tasks.ms send
var lane = lock(self.outgoing)
lane.value.back.append(value)
lane.value.wake()
lane.close()

# after
lane_send(self.outgoing, value)
```

- Ownership: a channel handle is a native handle (`Copy` class, like `NativeFile`); values sent move in; no payload ever leaves a box and returns, so there is no stale-value problem.
- Cancellation: a task parked in `send` or `receive` leaves the channel's wait list inside the runtime call (the job `WaitTicket` does in Manuscript).
- Errors: unchanged `ChannelError.Closed` and `Broken`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` | native channel object; result/entry tables beside the scope | Rust unit tests; `tasks`, `channels` fixtures; leak check |
| `crates/ms-lower` | generic native ops pass element descriptors; delete `shared_method` | e2e |
| `stdlib/tasks.ms`, `workers.ms`, `processes.ms` | rewritten on the native objects | existing fixtures |
| `stdlib/log.ms`, `router.ms` | writer task, event channel | log/router fixtures, new log-error fixture |
| `crates/ms-check`, `ms-clif`, `ms-mir` | delete guard special cases, `Shared` classification, ops used only by `Shared` | workspace tests |
| docs, tests | remove `Shared`/`lock`; document channels as the sharing story | `make docs`, `make conform` |

## Alternatives

- **Keep `Shared`, fix the guard.** Cheapest per change but keeps the box as the base and the special cases; the repeated reviews found no fix that is both small and sound.
- **Guard-free in-place cell.** Needs a mutable `Closeable` carrier, a new compiler feature, and keeps sharing as the base.
- **Owner tasks for everything.** Needs channels anyway; this proposal makes them native so they are fast enough.
- **Do nothing.** The guard glue and `lock` footguns remain.

## Staging and verification

1. Native channel + task channels and result slot. Gate: `make conform`, `scripts/leak-check.sh` on tasks fixtures, channel throughput not worse than today (measure sends per second at depth 1 and 16 before and after), 100k-task fixture.
2. Group and worker registries; `processes.ms` inbox. Gate: worker/process fixtures, leaks 0.
3. Logger writer task and router events. Gate: log throughput within 2x for one writer, correct ordering across 100 concurrent writers.
4. Delete `Shared`, `lock`, the guard and the special cases; docs; `make verify-full`.
- Go/no-go after stage 1: if channel throughput regresses by more than 2x or the native object needs more than about 600 lines, stop and report; the fallback is the guard-free cell.

## Open questions

- Logger write errors: deferred to `flush`/`close` (recommended, like async appenders), or a per-call reply channel (keeps immediate `Result`, costs a channel per call)? This changes `Logger` behavior and needs the owner's call.
- Should a channel carry any `T`, or only `Data`? Recommendation: any `T`, as task channels do today; worker channels stay `Data`.
