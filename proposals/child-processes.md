# Child processes and `fork` (design proposal)

Status: proposal, no code. Needs Chinmay's sign-off before implementation.
Direction (Chinmay, 2026-10-24): follow the JS `worker_threads` model for parallelism and extend it to processes; one proposal for worker threads, one for processes, and processes must be able to fork. Builds on `proposals/taskgroup.md` (approved): `TaskGroup` is the scope type and `Channel[T]` the one channel API. The worker-threads proposal is separate and shares the `Channel[T]` surface defined there. Revised 2026-10-24 per Chinmay: all platforms in the first release, no sendable rule, JSON instead of a new binary codec.

## Problem

Manuscript programs use one core. The runtime is one thread of stackful coroutines (`crates/DESIGN.md` decision 4), and tier-2 worker threads need per-thread runtime globals (allocator, fault context, cleanup stack, cancel flag, scheduler), which is a large change. Processes need none of that: each child has its own runtime. They also isolate faults: a child that faults exits 70 without touching the parent's heap.

Today a program can start a process (`Commands.spawn`, `@std/process.ms`) and talk bytes over OS pipes, but there is no way to run *Manuscript code* in a child, pass typed values, or bind the child's lifetime to a scope. Target program:

```manuscript
from "@std/tasks.ms" import TaskGroup, Sender, Receiver

def checksum(input: Receiver[Bytes], output: Sender[Int], seed: Int) -> Int:
    var total = seed
    for chunk in input:
        total = total + chunk.length()
    output.send(total)
    return total

def main():
    with TaskGroup[Int]() as group:
        let (to_child, from_child) = group.fork(checksum, 7)
        to_child.send(read_block())
        to_child.close()
        let results = group.results()
```

`group.fork(entry, argument)` starts the same executable running `entry`, scoped to the group; the group kills it if the scope exits early and joins it otherwise.

## Design

**What `fork` is.** Not POSIX `fork(2)`. The runtime is multithreaded (a blocking pool for DNS, workers coming), and `fork()` keeps only the calling thread while the child inherits any lock another thread held, plus the poller, pidfd and coroutine stacks. Windows has no `fork`. `fork` here is JS `child_process.fork`: **spawn the same executable, tell its runtime which exported function to run, and give it a token-guarded loopback connection back to the parent.** Parent state is never copied.

**Entry is a function item, not a string or closure.** `entry` must be a named top-level `export def` (any module), with the shape `def f(input: Receiver[In], output: Sender[Out], argument: A) -> R`, where `In`, `Out`, `A` and `R` are any types with a JSON form. The checker rejects lambdas, methods and nested functions at the call site; `In`, `Out`, `A` and `R` need a JSON form, which is checked when values are encoded. Compared with JS's `fork("path.js")` this catches typos and signature mismatches at compile time. The lowering records each referenced entry in a per-executable entry table (index → function plus `A`/`R` types); an entry that is never forked is dead code as usual. Parent and child are the same binary, so the table agrees by construction.

**Startup protocol.** The parent runs its own executable (`std::env::current_exe`; `/proc/self/exe` on Linux so a replaced binary on disk is not run) with env `MS_FORK_ENTRY=<index>` and `MS_FORK_IPC=<descriptor>`, plus the argument frame sent first over IPC. The runtime start path (`msrt_start`) checks `MS_FORK_ENTRY` before `main`: if set, it removes both variables from the environment seen by user code (so grandchildren and `environment()` never see them), reads the argument frame, runs the entry as the main task, and sends the result frame before exiting 0. User `args()`/`main` are untouched. Env was chosen over hidden argv because `msrt_args` already hides one selector and a second would need the same skip logic; env is cleared before user code runs.

**IPC channel (all platforms, one code path).** The parent binds a loopback listener (`127.0.0.1`, ephemeral port), puts the port and a random 128-bit token in `MS_FORK_IPC`, spawns the child, accepts exactly one connection that presents the token, then closes the listener. Sockets are what the poller already parks on in every platform (`poller.rs`: epoll/kqueue and mio sockets on Windows), so `send` parks when the buffer is full (backpressure), `receive` parks when empty, and both are cancellation points. This needs no descriptor inheritance, no `pre_exec` and no handle lists, so `spawn::start` only gains env and a `/dev/null` stdin, and Windows works like Linux. Cost: the port is reachable by other local users until the single accept, which the token makes harmless; a Unix-domain socketpair can replace it on Unix later without API change. Frames on the one connection: `argument`, `message(channel_id, bytes)`, `close(channel_id)`, `cancel`, `result`. The user endpoints are `Sender[In]` (parent; `Receiver[In]` in the child) and `Receiver[Out]`. Close of the sender delivers end-of-input; socket EOF with no `result` frame means the peer died.

**Serialization: JSON, reusing `@std/json.ms`.** Raw memory cannot cross: strings, lists, maps and records holding them contain heap pointers, and `Map`/`Set` carry a hash index, so only plain-bits values (`KIND_POD`: scalars, records of scalars) could be copied as bytes. Everything else needs a walk driven by a type descriptor, and `TypeDesc` has none for records and alternatives (`KIND_CUSTOM` is opaque function pointers), so a binary codec is new compiler work. Decision requested by the owner: when raw memory is out, piggyback on JSON. Messages, the argument and the result use the existing typed `stringify` and `parse[T]` (length-prefixed UTF-8 frames), already implemented for records, alternatives, Optional/Result, List/Set/Map, Bytes (base64), `Int`, and `BigInt`/`Decimal`. There is **no sendable rule**: like `stringify`, nothing is rejected at compile time, and a value with no JSON form (a handle, a closure, `Shared`) fails when encoded or decoded with `InvalidData`, which faults the sender or receiver naming the type. Known losses, documented rather than patched: `NaN` and infinities become `null` and fail to decode as `Float`; `Map` keys must be of the key types JSON lists; views are copied. A `max_message_bytes` bound (default 64 MiB) reuses `JsonLimits`. Parent and child are one binary, so no version negotiation is needed beyond the entry-table build id in the handshake. If measurement later shows JSON is the bottleneck, a binary format can replace the frame body without changing the API; that is not proposed now.

**Scope and lifetime.** `fork` and `process` are methods of `TaskGroup`, so a child never outlives its `with`:
- `group.fork(entry, argument) -> (Sender[In], Receiver[Out])`; the child's return value `R` is the group's `T` and appears in `results()` in spawn order. A group mixing tasks and forks uses one `T`.
- `group.process(program, arguments) -> Subprocess` registers a plain program (not Manuscript) with the group: it is killed and joined at scope exit. It contributes no result; exit codes remain data via `Subprocess.wait()`, as today.
- `results()`/`wait()` wait for children. `close()` (leaving the block, cancellation of the parent, or a signal) stops forked children cooperatively first: it sends a `cancel` frame, the child cancels its main task so shielded cleanups run, and after a grace period (default 5 s) the group is killed (`SIGKILL`, as `Subprocess.close` does) and joined. `Subprocess.close` alone kills immediately, so plain `process` children get no cleanup. Unix children run in their own process group, so grandchildren die too.
- Orphans: if the parent is killed without running cleanup, the child sees socket EOF, cancels its main task (shielded cleanups run, exit), and Linux also sets `PR_SET_PDEATHSIG(SIGKILL)` as a backstop. A leaked `Sender` in the parent (TaskGroup's known gap: captures of a cancelled or faulted task are not dropped) would delay that EOF, so stage 4 depends on the TaskGroup fix or on the cancel frame above.

**Faults.** A child fault runs its cleanups, writes the fault text to its stderr (inherited from the parent by default), and exits 70 with no `result` frame. The parent's runtime watches the child (pidfd on Linux; other platforms fall back to the existing slice polling) and, matching the approved TaskGroup v1 rule, a child fault **ends the parent with a fault** naming the entry and exit status, after the group's cleanups kill and join the siblings. Unlike in-process tasks the parent can observe the failure, so a later stage can offer `group.fork_catching(...)` returning `Result[R, ChildFault]` without any new runtime hook; not in v1. A child killed by a signal reports `-1` (as `Subprocess.wait` does) and is treated as a fault unless the group itself killed it.

**Stdio and environment.** The child inherits stdout and stderr and the environment; stdin is `/dev/null` (inheriting it makes two processes race for the terminal). Working directory is inherited. An optional `environment` and working directory override are v1.1.

**Platforms.** Linux, macOS and Windows ship together; nothing is feature-gated by platform. Per-platform parts: executable path from `std::env::current_exe`; exit watching by pidfd on Linux and the existing slice polling elsewhere; orphan protection by socket EOF everywhere, plus `PR_SET_PDEATHSIG` on Linux; Windows needs the job object created with `KILL_ON_JOB_CLOSE` and assigned at creation (today it is assigned after spawn, which is racy) so grandchildren die with the child.

**No shared memory in v1.** No mmap'd regions, atomics or locks; Values cross by copy only.

## Alternatives

1. **Do nothing.** Agents use `Commands.spawn` with the program's own executable plus hand-rolled byte pipes. No code runs in a child with types, no scope lifetime for it, and every user reinvents framing. Cheapest; leaves multi-core use to hand-built plumbing.
2. **POSIX `fork()`.** Rejected: multithreaded runtime (lock and poller state), not portable, copies the whole heap implicitly and breaks "one owner" at the OS level. Safe only before any thread starts, which the runtime does not guarantee.
3. **Fork a closure.** Rejected: closures capture owned state that would have to be serialized; entry functions have only declared, JSON-shaped inputs.
4. **Entry by string (`"module.ms", "main"`).** Possible (JS-style), but a typo is a runtime failure, the compiler cannot know which functions to keep or which types to encode. Function items give both.
5. **JSON or self-describing format over stdio.** Rejected above; stdio also collides with the child's user-visible stdout.
6. **Wait for worker threads.** Tier 2 threads need per-thread runtime globals. Processes work today with no change to `ms-rt` globals, so they are the earlier route to cores and also give crash isolation threads cannot.

## Cost and risks

- Evidence of benefit is design-level. No measurement here shows a workload that gains; the first stage that runs code must record exec-plus-startup latency of a fork child and serialization throughput of a large `List[Int]` and a `Bytes` blob against a plain pipe, and the benefit claim stands or falls on it. Static musl binaries start fast but a large binary is re-exec'd per child.
- Plumbing that does not exist yet: `spawn::start` takes only stdin/stdout/stderr pipes (no `pre_exec`, no extra fd, no `/dev/null` stdin), `msrt_start` has no pre-`main` dispatch (the entry runs through a new path beside `run_on_big_stack`), and `Child::wait` blocks the runtime thread, so waiting must use the pidfd/poller.
- Compiler work: entry-table emission, the call-site checks (function item, signature). Runtime: start-path hook, socket framing, parent-death handling.
- Dependency: the `Sender`/`Receiver` types and `TaskGroup` (TaskGroup stages 3 and 4). Fork can start with its own endpoint types behind the same API, but the public names must come from TaskGroup stage 4 to avoid two channel types.
- Security: child inherits the environment; the loopback listener accepts one connection that presents a random token, then closes.
- Interaction with `ms test`: it already runs each test in its own invocation with a selector, so the entry selector must not collide (own env var, checked first).

## Stages (each its own PR, auto-merge)

1. Docs: this design in canonical pages, DESIGN.md/VISION/expert entry. Needs TaskGroup stage 1.
2. Measure spawn-self latency and JSON round-trip throughput (large `List[Int]`, `Bytes`); round-trip tests for the supported types. No fork yet.
3. Entry table and start-path hook: run an exported function in a re-exec'd same executable with an argument and result frame, no channels.
4. IPC transport: loopback socket framing, `Sender`/`Receiver` over it, backpressure, EOF, oversize and malformed frames, parent-death cancel.
5. `TaskGroup.fork` and `.process`: scope join/kill, fault surfacing, sibling kill.
6. Diagnostics (a lambda or method passed to `fork`, `os.fork()`/`child_process.fork` shapes pointing to `group.fork`) and cheat sheet.
7. Windows hardening: job object with `KILL_ON_JOB_CLOSE` assigned at creation, and CI coverage on all three platforms (this stage is part of the first release, not optional).

## Reconciling `taskgroup.md`

Stage 1 updates `taskgroup.md`: the `spawn_worker("path.ms", ...)` string form is replaced by function items (as the worker-threads proposal already does), the sendable rule is dropped for processes (JSON failure at encode time instead; the worker-threads proposal decides for threads), and `crates/DESIGN.md` decision 4, `.experts/runtime.md` and VISION.md name fork. Mixed `T`: `fork` returns the endpoint pair while `R` joins the group's `results()`. `fork_catching` is deferred until the TaskGroup fault hook exists, because child faults are uncatchable in v1; the parent only sees an exit status.

## Open questions for the owner

- Function item (recommended) or string path as the entry.
- Child stdin `/dev/null` (recommended) or inherited.
- Channels inside messages across processes: not in v1 (recommended); JSON has no form for an endpoint, so it would need a separate handle-passing design.
