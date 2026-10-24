# TaskGroup: structured concurrency (design proposal)

Status: **approved by the owner on 2026-10-24 for staged implementation; nothing here is implemented yet.** Revised after a skeptic review.
Direction (Chinmay, 2026-10-24): tasks approach, type named `TaskGroup`, no async/await, `Channel[T]` with moving send/receive, single-threaded first.

## Problem

User code cannot run two things at once. The runtime already has stackful coroutines (`crates/ms-rt/src/task.rs`: `msrt_task_spawn/join/cancel/yield/sleep/current`, tokens), but only the stdlib I/O uses them. `crates/DESIGN.md` decision 4 (2026-10-19, owner direction) says the language has no `spawn`. This proposal reverses that decision for scoped tasks only. DESIGN.md decision 4, `.experts/runtime.md` ("the language has no concurrency runtime") and VISION.md must change with it.

Target program (fan-out, fail together, results owned):

```manuscript
from "@std/tasks.ms" import TaskGroup

def fetch_all(urls: List[String]) -> List[Int]:
    with TaskGroup[Int]() as group:
        for url in urls:
            group.spawn(lambda: fetch_size(url.clone()))
        return group.results()
```

## Design

**Type.** `TaskGroup[T]`: every child returns the same `T` (`Unit` for effect-only work; use an alternative for mixed results). It is a `Closeable` resource, so it is used with `with`. No handle type in v1: results come back in spawn order.

**API as built (supersedes the list below where they differ; owner direction 2026-10-24: timeouts are required, opt-in only).** `TaskGroup[T](timeout: Optional[Duration] = none)`; `spawn(work, timeout: Optional[Duration] = none) -> Task[T]`; `Task[T].result() -> Result[T, TaskError]` (once); `results() -> Result[List[T], TaskError]`; `wait() -> Result[Unit, TaskError]`; `TaskError` is `TimedOut | Cancelled`. A timeout is a watcher task that sleeps then cancels the target; the group limit counts from creation and a task uses the shorter limit. The group stays typed (`TaskGroup[T]`) because source methods cannot declare their own type parameters yet; an untyped group with `Worker[R]`-style handles needs that compiler support first.

**API (original, all in `@std/tasks.ms`):**
- `TaskGroup[T]()` creates a group bound to the current task.
- `spawn(work: Callable[[], T]) -> Unit`. Starts a child task; it first runs when the parent parks or yields (existing `msrt_task_spawn` behavior).
- `results() -> List[T]`. Waits for every child, returns owned results in spawn order. Faults if any child faulted.
- `wait() -> Unit` for `T = Unit`.
- `close()`. Cancels unfinished children, waits for all of them, then raises a pending child fault. Idempotent, may suspend (matches `Closeable`).

**Semantics.**
- The scope does not end until every child has finished: `close` always joins.
- Fault in a child (revised after review): faults are not catchable and a fault ends a task at its guard with status 1, so a Manuscript wrapper cannot observe it. v1 therefore keeps decision 3's behavior: **a fault in any child ends the process** (cleanups of that task run, exit 70), exactly as an unjoined fault does today. Catching a child fault and re-raising it in the parent needs a new runtime fault hook that notifies the group and a way to raise a primary fault from the parent; that is deferred to a later stage and listed as an open design item, not assumed.
- Parent cancelled (signal, shutdown, its own parent group): `close` cancels the children, then waits.
- Decided (owner, 2026-10-24): leaving the `with` block cancels tasks that are still running, then waits for them. Call `results()`/`wait()` before the block ends to collect work instead of cancelling it. A checker error for a block that can end with unjoined children is optional later work.

**Ownership.** `spawn` takes an escaping closure, which owns its captures (existing rule). A `Move` value captured by a spawned lambda moves in, so the parent cannot use it afterwards; mutating a captured `var` is already rejected for escaping closures; results return by value. `let ref` borrows and lending results must not be captured by an escaping closure; this needs a test and likely a sharper diagnostic, not new rules. `Shared[T]` is the documented opt-in refcounted type and is `Copy`-class, so it can cross a spawn. With one thread and `take`/`put` having no park between them this is sound. The "no shared mutable state" claim is therefore not absolute in v1. Recommend: allow `Shared` in v1, forbid it in a future `parallel` group (non-atomic counts).

**Channel (owner direction 2026-10-24: the type is `Channel[T]`).** One type, `Channel[T](capacity: Int)`, created once and passed to producers and consumers. It is a refcounted handle like `Shared[T]` (copying it adds a holder), so it can be captured by several spawned closures; the buffered values themselves are never shared, each is moved in by `send` and out by `receive`.
- `send(value: T) -> Unit` consumes the value, parks while the buffer is full, is a cancellation point. Faults if the channel is closed.
- `receive() -> Optional[T]` returns an owned value, `none` once the channel is closed and drained. Parks while empty.
- `close() -> Unit` is explicit and idempotent (an owner-less handle cannot know its last holder). Receivers wake with `none`. Closing is the sender side's job by convention; in a `TaskGroup` the usual shape is: producers send, the parent calls `close()` after `results()`.
- Iteration (`for item in channel`) is deferred until the stream/iterable protocol in `stdlib/streams.ms` is checked.

**Implementation shape (revised).** Externs cannot take closures, generics, or `var` params, and the extern rule says arguments are borrowed, so a consuming closure parameter needs an ABI rewording. Stage 2 is real compiler and runtime work, not a narrow addition: a closure-typed consuming extern parameter, a runtime trampoline that calls the closure and drops it on normal return, and a shim for `msrt_task_join` (its 0/1/2 outcome plus message does not fit the `Result` extern shape). `TaskGroup[T]` itself is Manuscript over those externs; results go through one `Shared[Optional[T]]` slot per child. Channel endpoints are runtime-owned refcounted extern types with a parked-waiter token each.

Known gap: captures of a task that is cancelled or faults are not dropped (only `with` cleanups run on the guard jump). A cancelled parent exits as cancelled (main task `process::exit`) rather than raising a fault. Stage 2 resolves this for tasks started by a group: the runtime releases the closure when the task ends by return or cancellation (a fault ends the process).

**Diagnostics (targeted, stage 5).**
- `async`/`await`: already rejected at `crates/ms-syntax/src/parser.rs:1486` ("call the function directly"); extend the text to mention `TaskGroup`.
- `go f()`, `spawn(...)` as a free function, `Promise`, `setTimeout`, `Thread`: a "use `TaskGroup.spawn` inside `with TaskGroup[T]() as group`" diagnostic. These are ordinary identifiers, so match only the foreign statement shapes, never reserve the words.
- Constructing a `TaskGroup` outside `with`: error.
- Capturing a `ref` borrow in a spawned closure: error naming the capture.

**Relation to workers.** Worker threads and processes are a separate proposal with their own `WorkerGroup[T]`; this proposal covers single-thread tasks only. `Channel[T]` is meant to be shared with that work, so its `T` is written as if it must be sendable (plain data, no handles, `ref` borrows, closures, `Shared` or `Resource`).

**Not in scope.** Workers and processes, detached tasks, timeouts/deadlines on groups, select over channels. `ms diagram` does not exist in `ms-cli` today; the task-tree view and "fault traces name the spawning scope" are a final stage and the second needs the trace format checked first.

## Alternatives

1. **Do nothing.** User code stays sequential; agents fan out via processes or not at all. Cheapest. Loses the concurrent server/fetch cases the owner wants.
2. **`List.parallel_map(f)` only.** Covers fan-out/join with no new type, no channel, no `with` generics, and 'any fault aborts' is already today's behavior. Still needs the trampoline and closure extern. Does not cover producer/consumer or long-lived workers. Reviewer judged this stronger than TaskGroup for v1; it is stage 2's natural first consumer.
3. **Go-style unscoped `spawn`.** Rejected: leaked tasks, no cleanup order, cannot be reconciled with `with`.
4. **async/await.** Rejected: function coloring; the runtime is already stackful.

## Cost and risks

- Evidence of benefit is design-level (no measurements): no benchmark here shows agent programs failing for lack of concurrency. Stage 3 should ship with a small agent-written example set to check first-try success.
- Real compiler work: closure-typed extern parameter (checker, lowering, ABI doc), new diagnostics, `with`/Resource interaction for a generic type.
- Runtime risks to verify before stage 3: faulting a task while the parent is parked in `join`; that an escaping closure's captures drop when a cancelled task unwinds; 256 MiB default stack address space per child (pass a smaller `stack_bytes` for group children).
- Docs surface: new `documentation/core-language/` page, cheat sheet (`ms guide`), conformance fixtures (spawn/join order, fault, cancel, channel close, ownership rejections), DESIGN.md decision 4, VISION.md, `.experts/runtime.md`.

## Stages (each its own PR, auto-merge)

1. Docs only: this design in canonical pages, decision 4 / VISION / expert entry updated.
2. Closure-taking extern + task externs + trampoline; runtime tests.
3. `TaskGroup[T]` in `@std/tasks.ms`: spawn/results/wait/close, fault and cancel propagation, conformance fixtures.
4. `Channel[T]`.
5. Diagnostics and cheat sheet.
6. `ms diagram` task tree and spawn-scope fault traces.

## Skeptical review findings (folded in above)

- Fault propagation as first written was unimplementable (no group notification, parent parked on one child, uncatchable faults, cancel exits main). Replaced with abort-on-fault v1.
- Capture drops on cancel/fault do not run; recorded as a known gap.
- Headline example needed `url.clone()` (loop variable borrows `urls`); fixed. Not run: no `ms` binary built.
- Evidence for the benefit remains design-level; decision 4 was deliberate owner direction.
