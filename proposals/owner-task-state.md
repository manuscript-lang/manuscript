# Owner tasks instead of `Shared` and `lock` for shared state

## Summary

- `Shared[T]` + `lock` is a cooperative RefCell with a wait queue. It cannot serve threads (`worker-threads.md` rejects `Shared` messages and atomic shared heaps), carries three compiler special cases (#1422), and is how user code is nudged to share mutable state.
- Proposed: make one task own a piece of mutable state and let everything else talk to it over a `Channel`. Serialization, ordering, and blocking I/O (the reason library code holds locks) move into the owner. No guard, no payload move, no stale value.
- The same code shape works between tasks today and between workers later, because messages are all that cross.
- Measured: an owner task handles 100,000 `Add` messages in 16 ms (160 ns each) against 2 ms for 100,000 lock/unlock round trips (20 ns each). About 8x slower per operation, so hot internals stay as they are.
- Scope: document and use the pattern for public code; stop exporting `lock`/`SharedGuard` to user code; convert only library sites where it fits; keep an internal `Shared` substrate for channels and task plumbing. Decision requested: approve that scope, in particular removing public `lock` after the library no longer needs it.

## Status

Proposal, 2026-10-29, checked against `origin/main` at `69d78f65`. Direction (Chinmay): "the question is can we do better than shared", then "make a proposal". Builds on the skeptic findings of `retire-shared.md` (guards are held across parking calls in `workers.ms`, `processes.ms`, `log.ms`, `tasks.ms`; a native lane is 600-900 Rust lines) and `shared-guard-consuming-close.md`. Nothing implemented.

## Problem

- Verified: all concurrent mutable state in the library is guarded by `lock`, including the substrate of channels themselves (`Lane` in `tasks.ms` is a `Shared`), so `Shared` cannot simply be deleted.
- Verified: a lock held across a parking call is how library code serializes I/O (`log.ms` `send`, `flush`; `workers.ms` `wait`; `processes.ms` `ProcessGroup.close`). Waiting tasks queue in the box wait queue.
- Verified: closures cannot take `var` parameters, so no scoped "edit the payload" API exists; hence the guard value and its hand-back problem (#1422).
- Verified: tasks run only when some task waits on a group (`tasks.ms` header), so an owner needs a driver: any `receive` or `result` call by a client parks and lets it run.
- Non-goals: cross-thread shared memory, making channels faster, changing task APIs.

## Design

Rule: mutable state shared by several parties lives in one task's locals; clients send requests over the channel `spawn` gives them.

Pattern, checked against current `main` (`/tmp` spike, prints `4999950000`):

```manuscript
import Channel from "@std/channels.ms"
import TaskGroup from "@std/tasks.ms"

type Request:
    case Add(n: Int)
    case Total

fn counter(ch: Channel[Int, Request]) Int:
    var total = 0
    while true:
        let next = ch.receive()
        if next.is_error(): break
        if not next.get().is_some(): break
        match next.get().get():
            Add(n): total += n
            Total:
                let _ = ch.send(total)
    return total
```

- The owner holds its state in a plain local `var`; no `Shared`, no guard, no `held`. Requests are processed in arrival order, which is the serialization a lock gave.
- Blocking work (a transport write, a child join) runs in the owner; clients parked on `receive` for the reply are woken when it posts.
- Ownership: request and reply types are moved over the channel. A `Resource` state (a file, a transport) is created inside or moved into the owner and closed when the owner ends, by the existing implicit close.
- Cancellation: cancelling the group cancels the owner; its locals drop as for any task. No lock to release.
- Errors: a closed channel gives `ChannelError.Closed` to clients, like any channel.
- Limits, said plainly: an API that must return a write error synchronously (`Logger.info -> Result`) becomes request/reply with the owner's result; state touched by a task that is not in a `TaskGroup` has no owner to run, so the pattern fits long-lived services, not tiny helpers.

Library conversions, each judged on its own:

| Site | Fits? | Plan |
| --- | --- | --- |
| `log.ms` shared transport (children share it) | yes if `create` receives a group or starts a private one | a logging owner task per logger family; deferred to a spike with throughput numbers |
| `processes.ms` registry and `started` counter | yes | owner or plain state of `ProcessGroup` once spawn goes through the group |
| `router.ms` test/tap state | yes | local state in the test harness |
| `Shared[List[Route]]` read per request | no sharing of mutation needed | stays a read-only share |
| `tasks.ms`, `workers.ms` lanes, result slots, registries | no, hot path | keep `Shared` internally |

- Public surface: stop exporting `lock` and `SharedGuard` from `@std/sync.ms` once no user-facing library API needs them; keep `share`/`get` for read-only handles. Library-internal use continues through a std-private entry, which the checker already supports for `take`/`put` (callable only from `@std/sync.ms`).
- Special cases: `guard_held`/`copy_if` stay until the internal substrate is replaced; this proposal does not claim to delete them, and says so.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| docs: concurrency guide | owner-task pattern with the example above; remove `lock` from `references.md`, `scopes.md` examples | doc example checks, `make docs` |
| `stdlib/log.ms` (spike) | owner-task transport | throughput bench vs lock; `log` fixtures |
| `stdlib/processes.ms`, `router.ms` | convert where it fits | existing fixtures |
| `stdlib/sync.ms` | un-export `lock`/`SharedGuard` after conversions | reject fixture, ownership fixtures rewritten without `lock` |
| tests | about 67 files mention `lock(` or `Shared[`; ownership fixtures that use `lock` as a resource get a local `Closeable` | `make conform` |
| `crates/ms-*` | unchanged in stage 1 | n/a |

## Alternatives

- **Do nothing.** Public `lock` stays; users who need shared state reach for it and its footguns (deadlock on relock, lock across I/O, stale guard). Cost grows with users, not with time.
- **Delete `Shared` (`retire-shared.md`).** Rejected by review: locks are held across parking calls today and native lanes cost 600-900 Rust lines.
- **Consuming close fix for the guard (`shared-guard-consuming-close.md`).** Removes the glue only; changes the checker for explicit `close()`. Independent of this proposal and can still be done for the internal substrate.
- **Atomic cross-thread `Shared`.** Rejected in `worker-threads.md`.
- **`Cell` with `replace` only.** Safe, but updates copy; fine for counters, wrong for queues and lists.

## Staging and verification

1. Docs and one `examples` fixture for the pattern; no library change. Gate: example runs under `make conform`.
2. Spike `log.ms` as an owner task. Go/no-go: log throughput within 2x of the lock version at 1 and 100 writers, no new leaks (`scripts/leak-check.sh`), cancellation fixtures pass. If it fails, the pattern stays documentation only and the library keeps `lock`.
3. Convert `processes.ms` and `router.ms` sites that fit; one PR per file.
4. Un-export `lock`/`SharedGuard`; rewrite the ownership fixtures; keep the std-private entry.

## Open questions

- Should a logger own its own `TaskGroup`, or should `create` take one? Recommendation: private group, closed with the logger, to keep `create` unchanged.
- Is removing public `lock` acceptable after stage 3? Recommendation: yes, but only if stage 2 passes; otherwise keep it documented as a low-level tool.
