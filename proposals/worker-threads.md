# Worker threads: design proposal

- Status: proposal, no code. Requires owner sign-off before implementation.
- Scope: in-process parallelism only. Child processes (including fork) are a separate proposal.
- Depends on: TaskGroup stages 2-4 (`taskgroup-proposal.md`) only for `Channel[T]` (stage 4 here). Stages 1-3 are independent.
- Owner direction (2026-10-24): `worker_threads`-style model; dedicated `WorkerGroup` type; `Channel` uppercase; no user-facing "sendable" concept; Linux, macOS and Windows from the first stage; send raw memory between threads.

## Problem

- Tasks (`TaskGroup`) interleave on one thread. CPU-bound work (hashing, parsing, compression, search) cannot use more than one core.
- Goal: parallel execution with task-like scoping, the same `Channel[T]` API, and no shared mutable state.

## Contract surface

Aligned with TaskGroup (generic methods on source types are not available, so the group stays typed):

```manuscript
from "@std/workers.ms" import WorkerGroup

def hash_chunk(chunk: Bytes) -> String:
    return sha256_hex(chunk)

def hash_all(chunks: List[Bytes]) -> Result[List[String], TaskError]:
    with WorkerGroup[String]() as group:
        for chunk in chunks:
            group.spawn(hash_chunk, chunk)
        return group.results()
```

- `WorkerGroup[T]`: `Closeable` in `@std/workers.ms`; every worker returns `T`.
- `spawn(f, arg, timeout: Duration = none) -> Worker[T]`; `Worker[T].result() -> Result[T, TaskError]`; group `results() -> Result[List[T], TaskError]` in spawn order; `wait() -> Result[Unit, TaskError]`. Same names, shapes and `TaskError` as `TaskGroup[T]`.
- Timeout is opt-in per worker and per group. On expiry the worker's cancel flag is set and `TaskError` reports a timeout once it stops; a worker with no cancellation point cannot be interrupted (see cancellation).
- `f` is a named top-level `def` with one argument (use a record for several). Lambdas, local defs and captures are rejected. No path string.
- `close()` (leaving `with`) cancels unfinished workers and joins them.
- Mixed result types: one group per `T`, or an alternative as `T`. Untyped group plus `Worker[R]` is deferred until the compiler has generic methods on source types (prerequisite, not in this proposal).
- Why not `TaskGroup.spawn_worker`: the boundary check and entry rule belong to one type; `TaskGroup` keeps closures.

## Design

### Isolate model
- A worker is one OS thread running an isolate: own allocator arena, scheduler and task tree, fault context, cleanup stack, drop queue, poller.
- An isolate may use a `TaskGroup` internally.
- No Manuscript value is shared between live isolates; ownership transfers on send. Non-atomic refcounts and the single-threaded allocator therefore stay valid inside an isolate.

### Transfer: raw memory move (threads)
- Same address space and binary, so pointers stay valid. A send moves the value's words to the receiver; the sender gives up ownership as for any move. No encoding, no copy; O(1) per send.
- The receiver owns the pointed-to blocks, so any isolate must be able to free any block:
  - arena registry that maps an address to its owning arena;
  - remote-free queue per arena for blocks freed by a non-owner thread.
- Today `StdHeap::dealloc` decides arena vs `System` by one `in_arena(STATE)` address test. With N arenas a foreign block would be routed to `System.dealloc`, which is heap corruption. The registry fixes this and is required, not an optimization.
- Cross-process transfer cannot use raw bits (pointers differ per address space); the processes proposal specifies JSON there.

### Worker-boundary type check
- No declared or documented "sendable" trait. The compiler rejects, as an ordinary type error, any worker argument, worker result or cross-worker `Channel[T]` payload that contains:
  - `Resource` values and handles (thread-affine fds and reactors);
  - `Shared[T]`, `Weak[T]` (non-atomic refcounts would race);
  - closures and function values;
  - `ref` borrows and views.
- Everything else (scalars, `String`, `Bytes`, collections, records, alternatives, `Sender`/`Receiver`) is accepted without annotation.
- The check cannot be dropped: without it, a `Shared` or handle crossing threads is a silent data race.
- It is derived from the existing ownership classes (`Copy`, `Move`, `Resource`, handle) in `ms-check`.

### Channel[T]
- API is TaskGroup's: `Channel[T](capacity)` returns `(Sender[T], Receiver[T])`.
- Transport follows endpoint location: in-isolate queue between tasks; cross-isolate bounded queue (mutex) holding moved values.
- Blocking: a receiver on an empty channel parks on a runtime token; a sender in another isolate posts that token and wakes the target poller. Full channels park the sender the same way.
- Closing: last `Sender` drop closes the channel; sender count is atomic across isolates. The channel core is the only cross-isolate refcounted object.
- Token wakeups need isolate id, per-isolate inbox and wake fd, and generation counts on token ids (the current global `INBOX` keyed by reusable ids would wake the wrong waiter). The blocking pool must post to the issuing isolate.

### Scope, cancellation, faults
- `close` (leaving `with`) cancels unfinished workers, then joins their threads.
- Cancellation: per-isolate atomic cancel flag set by the parent; the process-wide signal flag also reaches every isolate. Cancellation points are the existing ones (runtime calls, I/O, channel operations, sleep). A worker in a loop with none cannot be cancelled and `close` blocks on it (same as tasks).
- Fault in a worker (v1): run that isolate's cleanups, then end the process with exit 70, via one process-wide fault latch so a worker fault does not race main's cleanups and exit hooks.
- Parent-visible fault propagation is the item deferred jointly with TaskGroup.

### Runtime state classification
- Per-isolate: allocator `STATE`; `DROP_DEPTH`, `PENDING`; `CLEANUPS`, `GUARDS`, `SHIELD`, `FAULTING`, `SECONDARY`, `PRIMARY`, `GUARD_MESSAGE`, `PENDING_SIGNAL`; `TASK_CANCEL`; `STACK_LO`, `STACK_HI`; `SCHED`; `EQ` scratch; string `HINT`; poller state, `WAKE_FD`, `WAKER`; `TRAP`; debug counters (`STR_COUNTS`, `DROPS`, `FREED`, `ZERO_COPIES`).
- Process-wide, read-only after start: `TABLES`, argc/argv, `MAIN_FN`, `START_NANOS`, static string tables.
- Process-wide, synchronized: blocking pool, signal cancel flag, `EXIT_HOOKS` (needs a lock), profiler buffers.
- Needs rework: `PARKED` fd table (collides across isolates; becomes per-isolate), `MAIN_RESULT`, `TTY`, `CLOSED`, Windows `trap_windows` buffers.
- Compiled code reads `msrt_stack_limit` and `msrt_cancel_flag` directly in prologues and loops. Per-isolate versions are a codegen and ABI change in `ms-clif` and the LLVM path, not a `Global<T>` swap.
- `ms-std-*` statics each need classification: `ms-std-io` STDIN, `ms-std-terminal` ACTIVE/HOOKED/CURRENT, `ms-std-system` caches, `ms-std-net` thread-local reactors (hold arena objects and `Rc`), `ms-std-process` signal atomics, `ms-std-log`, `ms-std-fs`, `OnceLock`s in tls, hpack, time, process.
- I/O decisions: stdout and stderr go through one process-wide writer with line-atomic writes, flushed at exit and on fault; stdin is main-isolate only, and a worker read faults with a message.

### Mechanism
- Change `Global<T>` itself to thread-local storage (const-initialized, no lazy init). Every per-isolate static follows with no per-site edit.
- The process-wide statics (list above) move to a new explicit `Process<T>` cell (read-only or synchronized). The audit decides each; the default flips from "process" to "isolate".
- Arena as a fixed reserved virtual range per isolate: the owner of any block is `addr >> RANGE_BITS`. This gives O(1) owner lookup (fixes `StdHeap::dealloc`) without a registry table. Non-owner frees push onto the owner's lock-free remote-free stack, drained by the owner on its next allocation.
- Generated code reads only `msrt_stack_limit` (recursive functions' prologues) directly; make it a TLS load. `msrt_cancel_flag` is read by runtime calls, not generated code, so it stays inside the runtime. Per-worker cancel is a TLS flag set via the worker's atomic mailbox.
- Rust-side data in `ms-std-*` uses `System` in workers.
- Gate: single-isolate programs must not regress beyond noise on `bench/perf`. If TLS cost fails the gate, stop and redecide; no second code path.

### All platforms
- Linux, macOS and Windows in every stage; a stage is done only when its tests pass on all three in CI.
- Per-platform items:
  - thread start and join;
  - TLS access cost (static musl local-exec on Linux; unverified on macOS and Windows);
  - per-thread stack-overflow and SEGV handling (`sigaltstack` on Unix; vectored handler in `trap_windows.rs` on Windows; main thread only today);
  - per-isolate poller wake (epoll, kqueue, IOCP);
  - allocator arena (`StdHeap` is Linux-only; the ms-rt arena is not).

### Not in v1
- Shared memory, atomics, locks; transferring handles; detached workers; thread limit; worker pools; parent-visible fault propagation; workers spawning workers.

## Alternatives

- Do nothing:
  - Parallel CPU work stays out of process-internal reach; processes give it at higher startup and serialization cost.
  - Cheapest; viable if processes cover the need. No demand measurement exists for threads.
- Shared heap with atomics (Go/Rust style): rejected. Atomic refcounts and a thread-safe allocator tax every single-threaded program, and add race classes the ownership checker does not model.
- `List.parallel_map` only: rejected as the base mechanism. It needs the same per-thread runtime plus closures crossing threads. May layer on workers later for named functions.
- Worker from a module path string (JS style): rejected. Stringly typed, needs a second compile unit or dynamic load, no gain in a single binary.
- `TaskGroup.spawn_worker`: rejected in favor of `WorkerGroup` (see contract surface).

## Cost and risks

- Per-isolate state is the dominant cost: ~50 `Global<T>` statics, allocator and `StdHeap` owner logic, poller, fault/guard machinery, direct reads from generated code. An error here is a silent cross-thread data race.
- Single-thread performance regression from TLS (gated).
- Debuggability: `ms profile`, fault traces and exit hooks are single-isolate today.
- Evidence of benefit is design-level. Stage 6 must measure a CPU-bound example at 1, 2 and 4 workers.
- Recommendation from review: build workers only if processes prove too costly on a measured CPU-bound example; otherwise stop after stage 1.

## Stages (each its own PR, auto-merge on; all three platforms green)

1. Runtime refactor, one isolate: static audit (including `ms-std-*`), `Global<T>` becomes thread-local, `Process<T>` for the rest, reserved-range arenas with remote free, `stack_limit` via TLS. Benchmark-gated. Design pages (DESIGN.md decision 4, VISION, `.experts/runtime.md`) change after the gate passes.
2. Second isolate in runtime tests: thread start and join, cross-arena free, per-thread stack guard, cancel, fault latch.
3. Checker and library: worker-boundary check, named-def rule, `WorkerGroup`, `Worker[R]`; conformance fixtures.
4. Cross-isolate `Channel[T]` (separable; workers are useful without it).
5. Diagnostics, cheat sheet, scaling example at 1, 2, 4 workers.

## Open questions for the owner

- Confirm the compiler keeps the worker-boundary rejections (`Shared`, handles, closures, borrows); required for memory safety of raw moves.
- Stdout through one line-atomic process writer, stdin main-only: confirm.
- TLS gate (no single-thread regression; on failure we stop and redecide): confirm.
- Proceed now, or only after processes are measured?
