# Retire `Shared` and `lock`: purpose-built state for the cases that use them

## Summary

- `Shared[T]` + `lock` + `SharedGuard` is a cooperative RefCell with a wait queue, used only inside the standard library (about 45 `Shared[` and 36 `lock(` sites in five files). Nothing crosses an OS thread: `worker-threads.md` rejects `Shared` as a message and rejects atomic shared heaps.
- It carries three compiler special cases (`SharedGuard` glue in `ms-clif/src/lower.rs`, the part-closer skip in `ms-lower/src/close.rs:397`, lock-twice detection in `ms-check/src/constfaults.rs:116`; #1422), and the guard owns the payload by move, so closing it leaves stale bits.
- Verified: no stdlib critical section suspends while the guard is held, so contention never occurs in the library. The wait queue serves only fixtures that sleep while holding a lock.
- Proposed: replace each use with the thing it actually is. Task and worker plumbing becomes runtime-owned state behind unchanged APIs; read-only sharing keeps a minimal `Shared` (`share`, `get`); the few remaining state holders are converted one by one. Then delete `lock`, `SharedGuard`, `take`/`put`, the wait queue and the three special cases.
- Decision requested: approve removing `lock` from the public language (a user-visible removal), and the staged order below. A go/no-go gate after stage 2 decides whether stage 3 proceeds or `Shared` stays with the consuming-close fix.

## Status

Proposal, 2026-10-29, checked against `origin/main` at `69d78f65`. Direction (Chinmay): "shared was meant as way to share data between threads, i'm not sure if it's addressing that use case correctly now"; then "can we address those use cases with better abstraction and get rid of shared?" and "write up a proposal and do skeptic review". Supersedes `shared-guard-consuming-close.md`, whose skeptic review (2026-10-29) found a consuming close does not move the binding in the checker and the clone-then-drop rewrite is unsound across a faulting `put`. Nothing implemented.

## Problem

Verified inventory (`grep` of `Shared[` / `lock(`):

| File | `lock(` | What the shared state is | What it needs |
| --- | --- | --- | --- |
| `tasks.ms` | 11 | `Lane` (queue, wait tokens, closed flags) per direction; per-task result slot `Shared[List[T]]`; group registry `Shared[Map[Int, Entry]]` | queue + park/wake; one-shot slot; registry |
| `workers.ms` | 3 | worker registry; per-worker `ended` list | registry; slot |
| `processes.ms` | 8 | `Inbox` (pending bytes, finished, result, closed) per end; open-process registry; started counter | state shared by an end and its reader; registry; counter |
| `log.ms` | 4 | `Shared[Transport]` shared by a logger and its children | one writer handle with several holders |
| `router.ms` | 10 | `Shared[List[Route]]` read per request (`routes.get()`); test and tap state | immutable share; two small mutable records |

- Verified: every critical section is short. `claim_room`, `send`, `receive` (`tasks.ms`) release the guard before `msrt_channel_park`; `next_frame` (`processes.ms`) calls `state.close()` before `msstd_process_ipc_wait_reader`. Tasks switch only at waits, so these sections cannot interleave.
- Verified: the only code that holds a guard across a suspension is test fixtures (`shared-lock-contention`, `shared-lock-timeouts`, `shared-lock-deadlock`, `shared-lock-survives-cancellation`). They exercise the wait queue and cancel-while-locked, which no library code relies on.
- Verified: closures cannot take `var` parameters (`fn(var List[Int]) Unit` is a parse error), so a scoped "edit the payload" callback API is not expressible; this is why the guard value exists.
- Verified: the guard is a general RefCell, not a thread tool. Making it work for threads would need atomics, which the project rejected.
- Non-goals: cross-thread shared state (separate design if wanted; channels remain the thread story), changing channel or task APIs, `Data`/worker transfer rules.

## Design

Rule: shared state belongs to the abstraction that owns the meaning, not to a general box.

1. **Immutable sharing stays small.** `Shared[T]` keeps `share(value)` and `get() ref T`; `lock`, `take`, `put`, `locked`, `id` and `SharedGuard` go. Router routes keep it (a per-request closure chain needs a cheap-to-copy read-only handle).
2. **Task and worker plumbing becomes runtime-owned.** The runtime already tracks tasks by handle (`msrt_scope_spawn`, `msrt_scope_join`), channel groups (`msrt_channel_group_*`) and wait queues (`msrt_waitq_*`). Add small generic natives and keep every Manuscript API as is:
   - a one-shot result slot owned by the scope entry, read by `collect` (replaces `Shared[List[T]]`);
   - a message lane (bounded queue plus closed flags plus wait tokens) as a runtime handle, replacing `Lane` and `WaitTicket` (the worker pipe, `msrt_pipe_*`, already works this way);
   - the group registry as runtime state keyed by scope and handle (replaces `Shared[Map[Int, Entry]]`, `Shared[List[Worker]]`).
3. **Remaining holders are converted one at a time**, each by the smallest change that removes sharing:
   - `processes.ms` `Inbox`: state of one IPC end; move it into the native link record it already pairs with (`NativeLink`), or hold it by value in the transport if the reader and the end share one owner.
   - `log.ms`: children share the parent's transport; hold the transport by one owning logger and give children a handle to it (same `Shared` read handle, writes through a transport method that does not need a payload move).
   - `router.ms` test and tap state: owned by the test harness; replace with plain `var` state captured once, or a lane-like runtime counter.
   - `processes.ms` registry and `started` counter: same registry primitive as stage 2.
4. **Delete.** `lock`, `SharedGuard`, `Ticket`, the box wait queue (`msrt_waitq_*` if no other user), `taken` flag and `take`/`put` in `sharedbuilder.rs`, `guard_held`/`copy_if`, `close.rs:397`, `constfaults.rs` lock tracking, the four lock fixtures and `reject/shared-relock.ms`, docs.

Before/after (user code unaffected; the library):

```manuscript
# before, tasks.ms
var lane = lock(self.outgoing)
lane.value.back.append(value)
lane.value.wake()
lane.close()

# after: the lane is a runtime handle
lane_send(self.outgoing, value)
```

- Ownership: runtime handles are `Resource`-style nominal types (`owned-handles.md`), closed with their group. A task's end closes when the task ends, as today.
- Cancellation: unchanged for tasks; a task cancelled while parked on a lane removes its token inside the runtime call instead of through `WaitTicket`.
- Errors: closed lane returns `ChannelError.Closed` as today.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` | lane, result slot, registry natives; remove box wait queue at the end | `tasks`, `channels`, `workers` fixtures; Rust unit tests |
| `stdlib/tasks.ms`, `workers.ms` | drop `Lane`, `WaitTicket`, `Shared` fields; call natives | existing e2e and conformance, 20k-task fixture timing |
| `stdlib/processes.ms`, `log.ms`, `router.ms` | per-site conversion | `processes`, `log`, `router` fixtures |
| `stdlib/shared.ms`, `sync.ms` | shrink to `share`/`get`, then delete `sync.ms` | `shared.ms` fixture, docs |
| `crates/ms-lower` `sharedbuilder.rs`, `close.rs`, `with.rs` users | remove `take`/`put`/`locked`/`id`, SharedGuard part-closer skip | `cargo nextest run --workspace` |
| `crates/ms-clif` `lower.rs` | delete `guard_held`, `copy_if` | leak check |
| `crates/ms-check` `constfaults.rs` | delete lock tracking and `shared-relock` rule | reject corpus |
| docs, VS Code/LSP data | remove `lock`/`SharedGuard`; document `Shared` as read-only share | `make docs` |

## Alternatives

- **Do nothing.** Keeps three special cases, a public footgun (lock-twice deadlock, stale guard), and a tool that suggests thread sharing it cannot provide. Cost of waiting is low per day, so this loses only if the removal is cheap; stage 2's measurement decides.
- **Consuming close for the guard.** Needs checker changes (a consuming receiver must move the binding), a sound field-take pass and a prelude `drop`; benefit is hygiene for one type. Fallback if the gate in stage 2 fails.
- **Cell with `replace`/`swap` only.** Memory safe with no guard, but updates become read-copy-write, O(n) for queues; fine for counters only.
- **Ref field guard** (`value: ref T`, #1908): read-only views; no mutable form, so writes are not expressible. Hypothesis, not checked.
- **Cross-thread `Shared` with atomics.** Rejected by `worker-threads.md`.

## Staging and verification

1. Runtime natives (slot, lane, registry) with Rust tests; no source change.
2. Convert `tasks.ms` and `workers.ms`. Gates: `make conform`, `cargo nextest run --workspace`, `scripts/leak-check.sh` on tasks/workers fixtures, 20k-task and large-payload timings not worse than today. **Go/no-go:** count the remaining `lock(` sites. If more than the stage 3 list above, or any stage 2 benchmark regresses, stop and take the consuming-close fallback.
3. Convert `processes.ms`, `log.ms`, `router.ms`, one PR per file.
4. Delete `lock`, `SharedGuard`, special cases, fixtures, docs; `make verify-full`.

## Open questions

- Remove `lock` from the public language, with no replacement for user code that guards its own `Shared` state? Recommendation: yes; a user needing shared mutable state across tasks uses a channel or an owner task. The lock fixtures that sleep while holding encode no stdlib need.
- Keep the name `Shared` for the read-only handle? Recommendation: yes, to avoid a rename across the docs; revisit with the final API.
