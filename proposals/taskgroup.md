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

**API (all in `@std/tasks.ms`):**
- `TaskGroup[T]()` creates a group bound to the current task.
- `spawn(work: Callable[[], T]) -> Unit`. Starts a child task; it first runs when the parent parks or yields (existing `msrt_task_spawn` behavior).
- `results() -> List[T]`. Waits for every child, returns owned results in spawn order. Faults if any child faulted.
- `wait() -> Unit` for `T = Unit`.
- `close()`. Cancels unfinished children, waits for all of them, then raises a pending child fault. Idempotent, may suspend (matches `Closeable`).

**Semantics.**
- The scope does not end until every child has finished: `close` always joins.
- Fault in a child (revised after review): faults are not catchable and a fault ends a task at its guard with status 1, so a Manuscript wrapper cannot observe it. v1 therefore keeps decision 3's behavior: **a fault in any child ends the process** (cleanups of that task run, exit 70), exactly as an unjoined fault does today. Catching a child fault and re-raising it in the parent needs a new runtime fault hook that notifies the group and a way to raise a primary fault from the parent; that is deferred to a later stage and listed as an open design item, not assumed.
- Parent cancelled (signal, shutdown, its own parent group): `close` cancels the children, then waits.
- Open question for the owner: `with` cannot tell a normal end from an exit by `return`/`try`, so a block that ends without `results()`/`wait()` cancels its children. Trio waits instead. Recommend: cancel, plus a checker error when a `TaskGroup` block can reach its end with children possibly unjoined and no `results()`/`wait()` call (stage 3). The alternative (give `Closeable.close` the exit kind) changes a core contract.

**Ownership.** `spawn` takes an escaping closure, which owns its captures (existing rule). A `Move` value captured by a spawned lambda moves in, so the parent cannot use it afterwards; mutating a captured `var` is already rejected for escaping closures; results return by value. `let ref` borrows and lending results must not be captured by an escaping closure; this needs a test and likely a sharper diagnostic, not new rules. `Shared[T]` is the documented opt-in refcounted type and is `Copy`-class, so it can cross a spawn. With one thread and `take`/`put` having no park between them this is sound. The "no shared mutable state" claim is therefore not absolute in v1. Recommend: allow `Shared` in v1, forbid it in a future `parallel` group (non-atomic counts).

**Channel.** One owner per value means a single `Channel` object cannot sit in both a producer and a consumer closure. So: `channel[T](capacity: Int) -> (Sender[T], Receiver[T])`.
- `Sender.send(value: T) -> Unit` consumes the value, parks while full, is a cancellation point. `Sender.clone()` adds a producer.
- `Receiver.receive() -> Optional[T]` returns an owned value, `None` once every sender is dropped and the buffer is empty. Parks while empty.
- Each endpoint is move-only; dropping the last sender closes the channel. A receiver dropped early makes `send` return a closed result (final shape, `Result` vs `Optional`, decided in stage 4).
- Iteration (`for item in receiver`) is deferred until the stream/iterable protocol in `stdlib/streams.ms` is checked.

**Implementation shape (revised).** Externs cannot take closures, generics, or `var` params, and the extern rule says arguments are borrowed, so a consuming closure parameter needs an ABI rewording. Stage 2 is real compiler and runtime work, not a narrow addition: a closure-typed consuming extern parameter, a runtime trampoline that calls the closure and drops it on normal return, and a shim for `msrt_task_join` (its 0/1/2 outcome plus message does not fit the `Result` extern shape). `TaskGroup[T]` itself is Manuscript over those externs; results go through one `Shared[Optional[T]]` slot per child. Channel endpoints are runtime-owned refcounted extern types with a parked-waiter token each.

Known gap: captures of a task that is cancelled or faults are not dropped (only `with` cleanups run on the guard jump). A leaked `Sender` means its `Receiver` never sees close, and a cancelled parent exits as cancelled (main task `process::exit`) rather than raising a fault. Stage 2 must either run capture drops on the guard exit or document the leak; stage 4 depends on it.

**Diagnostics (targeted, stage 5).**
- `async`/`await`: already rejected at `crates/ms-syntax/src/parser.rs:1486` ("call the function directly"); extend the text to mention `TaskGroup`.
- `go f()`, `spawn(...)` as a free function, `Promise`, `setTimeout`, `Thread`: a "use `TaskGroup.spawn` inside `with TaskGroup[T]() as group`" diagnostic. These are ordinary identifiers, so match only the foreign statement shapes, never reserve the words.
- Constructing a `TaskGroup` outside `with`: error.
- Capturing a `ref` borrow in a spawned closure: error naming the capture.

**Planned path for parallelism (direction: JS `worker_threads` style, extending to processes).** v1 must not preclude it, so:
- One `Channel[T]` API (`Sender`/`Receiver`) across tasks, workers and processes; only the transport differs. The v1 endpoints keep an API that does not depend on being in-process.
- A "sendable" type rule decides what crosses a worker or process boundary: plain data (scalars, String, Bytes, List/Map/Set/records/alternatives of sendable types, and `Sender`/`Receiver` of sendable `T`). No handles, `ref` borrows, closures, `Shared`, or `Resource`. Same-thread tasks are not restricted by it, but channel `T` should be written as if it were sendable. Checker rule arrives with the worker stage.
- A worker starts from an exported module function (`group.spawn_worker("path.ms", "main", args)`), never a closure, so no captured state needs serializing or sharing. Arguments and the channel endpoints are the only inputs.
- Workers are scoped like tasks: same group contract (the group joins/cancels them on close), same fault rule at first (abort), so `TaskGroup` stays the one scope type. Process workers add transport (pipes) and exit status, not new scoping.
- No shared memory, no Atomics, no mutexes. `Shared` is not sendable.
- **Tier 2 (after tier 1 lands):** a worker is its own runtime thread with its own heap, scheduler and task tree. The `ms-rt` globals (allocator state, fault context, cleanup stack, cancel flag, scheduler) become per-thread. This is a large runtime change and its own proposal and review before any code; tier 1 changes nothing here.
- Channel transport by endpoint location: a queue between tasks, a buffer move between workers (value moved, not shared), serialization between processes.
- Child processes are scoped in a `TaskGroup` too; cancelling or closing kills the child's process group through the existing process module.

**Not in scope.** Workers/processes (above), detached tasks, timeouts/deadlines on groups, select over channels. `ms diagram` does not exist in `ms-cli` today; the task-tree view and "fault traces name the spawning scope" are a final stage and the second needs the trace format checked first.

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
4. `channel[T]`, `Sender`, `Receiver`.
5. Diagnostics and cheat sheet.
6. `ms diagram` task tree and spawn-scope fault traces.

## Skeptical review findings (folded in above)

- Fault propagation as first written was unimplementable (no group notification, parent parked on one child, uncatchable faults, cancel exits main). Replaced with abort-on-fault v1.
- Capture drops on cancel/fault do not run; recorded as a known gap.
- Headline example needed `url.clone()` (loop variable borrows `urls`); fixed. Not run: no `ms` binary built.
- Evidence for the benefit remains design-level; decision 4 was deliberate owner direction.
