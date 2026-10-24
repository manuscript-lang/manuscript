# TaskGroup: scoped concurrent tasks

Status: **approved by the owner on 2026-10-24.** Stages 1 to 3 are implemented (PR #1160, PR #1166); the rest is planned.
Direction (Chinmay, 2026-10-24): the tasks approach, type named `TaskGroup`, no async/await, timeouts required but opt-in, `Channel[T]` for passing values.
Worker threads and processes are a separate proposal (`WorkerGroup`); nothing here depends on it.

## Problem

User code cannot run two things at once. The runtime already has stackful coroutines (`crates/ms-rt/src/task.rs`), but only the standard-library I/O uses them. `crates/DESIGN.md` decision 4 said the language has no `spawn`; this proposal reverses that for scoped tasks only, and DESIGN.md, VISION.md and `.experts/runtime.md` say so.

## What is included

| Item | Stage | Status |
| --- | --- | --- |
| `TaskGroup[T]` in `@std/tasks.ms`, used with `with`; leaving the block cancels unfinished tasks and waits for them | 3 | built |
| `spawn(work, timeout:) -> Task[T]` and `Task[T].result() -> Result[T, TaskError]` | 3 | built |
| `results()` (all results in start order) and `wait()` | 3 | built |
| Opt-in timeouts: per task and per group, `TaskError.TimedOut` / `Cancelled` | 3 | built |
| Runtime support: `msrt_tasks_spawn/join/cancel`, closure-typed `extern` parameters, task-owned closures released on return or cancellation | 2 | built |
| Docs chapter, conformance fixture, LSP snapshots | 1 to 3 | built |
| `Channel[T]`: `send` moves a value in, `receive` returns an owned value, `close`; single thread | 4 | planned |
| Diagnostics: `go f()`, `spawn(...)` as a free function, `Promise`, `setTimeout`, a `TaskGroup` outside `with`, a `ref` borrow captured by a spawned closure; `async`/`await` text mentions `TaskGroup` | 5 | planned |
| Cheat sheet (`ms guide`) entry; `ms diagram` task tree and spawn-scope fault traces | 5, 6 | planned |
| Catching a child fault in the parent instead of ending the program | later | open item |

## What is excluded

- Worker threads, processes, `WorkerGroup`, any sendable-type rule beyond writing `Channel[T]`'s `T` as if it must be sendable.
- Detached tasks, `async`/`await`, callbacks as a concurrency primitive, shared mutable state between tasks, mutexes.
- A default timeout. A task has no limit unless one is given.
- Select over channels, deadlines that move, retry policies.
- An untyped group with mixed result types: needs generic methods on source types, which the compiler does not support yet. Today a group has one result type `T` (`Unit` for effect-only work, an alternative for mixed results).

## Design

**Surface.**

```manuscript
from "@std/tasks.ms" import TaskGroup

def fetch_all(urls: List[String]) -> Result[List[Int], TaskError]:
    with TaskGroup[Int](timeout: some(duration(5000000000))) as group:
        for url in urls:
            group.spawn(lambda: fetch_size(url.clone()))
        return group.results()
```

- `TaskGroup[T](timeout: Optional[Duration] = none)`: a `Closeable` scope. `timeout` limits every task in the group, counted from the group's creation.
- `spawn(work: Callable[[], T], timeout: Optional[Duration] = none) -> Task[T]`: starts a task. It first runs when the caller waits. A task takes the shorter of its own limit and the group's remaining time.
- `Task[T].result() -> Result[T, TaskError]`: waits for the task. Takes the result, so call it once (a second call faults).
- `results() -> Result[List[T], TaskError]`: waits for every task, results in start order, or the first task's error. `wait() -> Result[Unit, TaskError]` waits for all and reports an error if any ended without a result.
- `TaskError` is `TimedOut | Cancelled`; it implements `Error`.

**Scope.** `close` (run by `with` on every exit) cancels tasks not yet collected, then waits for them, so no task outlives its block. To keep the work, call `results()`, `wait()` or `result()` before the block ends. This is the owner's decision (2026-10-24).

**Timeouts.** Opt-in only. A limited task gets a watcher task that sleeps for the limit, marks the task timed out, and cancels it; collecting the task cancels its watcher. A cancelled task has no result: `result()` returns `TimedOut` if the limit fired, otherwise `Cancelled`. A negative timeout faults. A task that finishes just as its limit fires keeps its result.

**Cancellation and faults.** Cancelling the waiting task unwinds it and `close` cancels its tasks, through the existing per-task cancel flag. Faults cannot be caught, so a fault in any task ends the program (exit 70) after that task's cleanups, as an unjoined fault does today. Catching a child fault in the parent needs a runtime hook and is an open item.

**Ownership.** `spawn` takes a function value that outlives the call, so the closure owns its captures: a captured value moves in and the caller cannot use it afterwards; mutating a captured `var` is already rejected for such closures; results come back by value. Borrows (`let ref`, lending results) must not be captured; the diagnostic for that is stage 5. `Shared[T]` can cross a spawn on one thread (take/put have no wait between them); it is not part of any future sendable rule.

**Channel (stage 4).** `Channel[T](capacity: Int)` is a refcounted handle like `Shared[T]`, so several closures can hold it; the buffered values are never shared. `send(value: T)` consumes the value and waits while the buffer is full; `receive() -> Optional[T]` returns an owned value, `none` once the channel is closed and drained; `close()` is explicit and idempotent.

## Implementation

- Runtime (`ms-rt`): `msrt_tasks_spawn(closure)` retains the closure, starts a task with the new `SPAWN_FATAL` flag, and releases the closure when the task ends by return or cancellation. `msrt_tasks_join` returns 0 (done or already collected) or 1 (cancelled) and unwinds the caller if the caller is cancelled. `msrt_tasks_cancel`.
- Compiler: an `extern def` parameter of function type passes the closure object, lent (the native retains what it keeps). Ownership already treats native function arguments as consumed. A `with` binding whose `close` is in a generic `impl` now binds the impl's type variables.
- Library: `@std/tasks.ms` is Manuscript over three externs. Results travel in a `Shared[List[T]]` slot the task fills with a freshly built list.

## Alternatives

1. **Do nothing.** Code stays sequential. Cheapest; loses concurrent fetches and servers.
2. **`List.parallel_map(f)` only.** Smaller (no `with`, no handles), but no timeouts per task, no producer/consumer, and it still needs the closure extern.
3. **Unscoped `spawn`.** Rejected: leaked tasks and no cleanup order.
4. **async/await.** Rejected: function coloring; the runtime is already stackful.

## Risks and known gaps

- The benefit is design-level; no benchmark shows programs failing for lack of concurrency. Examples to check first-try success by agents are planned with stage 5.
- Two pre-existing compiler bugs were hit and worked around: issue #1167 (`Shared[List]` append-after-take frees the buffer; `Shared[Optional[Int]]` misreads) and source methods cannot declare type parameters.
- Each task reserves 16 MiB of address space for its stack (committed lazily).
- A deadlock where every task waits ends the program (exit 70), as it does for the existing runtime.
