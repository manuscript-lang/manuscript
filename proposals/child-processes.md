# Child processes and `fork` (design proposal)

Status: proposal, no code. Needs Chinmay's sign-off before implementation.
Direction (Chinmay, 2026-10-24): follow the JS `worker_threads` model for parallelism and extend it to processes; one proposal for worker threads, one for processes, and processes must be able to fork. Builds on `proposals/taskgroup.md` (approved): `TaskGroup` is the scope type and `Channel[T]` the one channel API. The worker-threads proposal is separate and shares the sendable rule and `Channel[T]` surface defined there.

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

**What `fork` is.** Not POSIX `fork(2)`. The runtime is multithreaded (a blocking pool for DNS, workers coming), and `fork()` keeps only the calling thread while the child inherits any lock another thread held, plus the poller, pidfd and coroutine stacks. Windows has no `fork`. `fork` here is JS `child_process.fork`: **spawn the same executable, tell its runtime which exported function to run, and hand it one inherited IPC descriptor.** Parent state is never copied.

**Entry is a function item, not a string or closure.** `entry` must be a named top-level `export def` (any module), with the shape `def f(input: Receiver[In], output: Sender[Out], argument: A) -> R`, where `In`, `Out`, `A` and `R` are sendable. The checker rejects lambdas, methods, nested functions and non-sendable types at the call site. Compared with JS's `fork("path.js")` this catches typos and signature mismatches at compile time. The lowering records each referenced entry in a per-executable entry table (index → function plus a codec for `A`/`R`); an entry that is never forked is dead code as usual. Parent and child are the same binary, so the table agrees by construction.

**Startup protocol.** The parent runs `/proc/self/exe` (Unix; `info().executable` elsewhere, so a replaced binary on disk is not run) with env `MS_FORK_ENTRY=<index>` and `MS_FORK_IPC=<descriptor>`, plus the argument frame sent first over IPC. The runtime start path (`msrt_start`) checks `MS_FORK_ENTRY` before `main`: if set, it removes both variables from the environment seen by user code (so grandchildren and `environment()` never see them), reads the argument frame, runs the entry as the main task, and sends the result frame before exiting 0. User `args()`/`main` are untouched. Env was chosen over hidden argv because `msrt_args` already hides one selector and a second would need the same skip logic; env is cleared before user code runs.

**IPC channel.** Unix: a `socketpair(AF_UNIX, SOCK_STREAM)` created by the parent; the child end is `dup2`'d to a fixed descriptor in `pre_exec` (async-signal-safe) and the rest are `CLOEXEC`. Both ends are nonblocking and parked on the existing poller, so `send` parks when the socket buffer is full (backpressure) and `receive` parks when empty, and both are cancellation points like other I/O. One socket carries both directions and multiplexes frames: `argument`, `message(channel_id, bytes)`, `close(channel_id)`, `result`. The two user endpoints are `Sender[In]` (parent side, `Receiver[In]` in the child) and `Receiver[Out]`. `close`/drop of the sender delivers end-of-input; EOF of the socket with no `result` frame means the peer died.

**Serialization.** Both sides are the same executable, so the format does not need to be self-describing or portable. Recommendation: a compact, type-directed binary encoding generated per sendable type: fixed-width little-endian ints, IEEE bits for floats, length-prefixed String/Bytes (strings validated as UTF-8 on decode), count-prefixed List, Map and Set in insertion order, a tag byte per alternative case, fields in declaration order. The lowering already generates deep `.clone()` per type; the codec mirrors that traversal, so it is a sibling of existing code, not a new representation layer. The handshake carries a build id (hash of the entry table) and refuses a mismatch. A message larger than `max_message_bytes` (default 64 MiB, settable per fork) faults the sender. A malformed frame faults the receiver; it never constructs a value of the wrong type.
Rejected: JSON (`@std/json.ms`) loses `Int` precision above 2^53 in common readers, cannot carry `Bytes`/NaN/non-string-keyed maps without conventions, and costs a parse plus a schema check both ways. JSON can be a user-level choice (send `String`).

**Sendable (one predicate, shared with the TaskGroup and worker-threads proposals).** `is_sendable(ty)`: the type is `Copy`, or `Move` and built from scalars, String, Bytes, List/Map/Set/Optional/Result, records and alternatives of sendable parts, and `Sender[T]`/`Receiver[T]` with sendable `T`. Not sendable: `Resource` values, handles, `Shared`, `Weak`, closures and function values, `ref` borrows and views. Entry points are named top-level defs (same rule as `spawn_worker`). The transport is chosen by where the endpoints live (`Channel[T]`), here a socket carrying serialized frames. One process-specific limit: sending an endpoint inside a message needs descriptor passing (`SCM_RIGHTS`; handle duplication on Windows), so v1 processes accept `Sender`/`Receiver` only as the two entry endpoints, never inside a message. The shared predicate stays one function with a boundary parameter; only `process` adds this exclusion.

**Scope and lifetime.** `fork` and `process` are methods of `TaskGroup`, so a child never outlives its `with`:
- `group.fork(entry, argument) -> (Sender[In], Receiver[Out])`; the child's return value `R` is the group's `T` and appears in `results()` in spawn order. A group mixing tasks and forks uses one `T`.
- `group.process(program, arguments) -> Subprocess` registers a plain program (not Manuscript) with the group: it is killed and joined at scope exit. It contributes no result; exit codes remain data via `Subprocess.wait()`, as today.
- `results()`/`wait()` wait for children. `close()` (leaving the block, cancellation of the parent, or a signal) kills each child's process group (`SIGTERM` is not used: the existing `Subprocess.close` semantics, kill the group, join, then kill leftovers) and joins it. Unix children run in their own process group, so grandchildren die too; Windows uses the job object `Child::new` already creates.
- Orphans: if the parent is killed without running cleanup, the child sees socket EOF, cancels its main task (shielded cleanups run, exit), and on Linux also sets `PR_SET_PDEATHSIG(SIGKILL)` as a backstop.

**Faults.** A child fault runs its cleanups, writes the fault text to its stderr (inherited from the parent by default), and exits 70 with no `result` frame. The parent's runtime watches the child (pidfd/job) and, matching the approved TaskGroup v1 rule, a child fault **ends the parent with a fault** naming the entry and exit status, after the group's cleanups kill and join the siblings. Unlike in-process tasks the parent can observe the failure, so a later stage can offer `group.fork_catching(...)` returning `Result[R, ChildFault]` without any new runtime hook; not in v1. A child killed by a signal reports `-1` (as `Subprocess.wait` does) and is treated as a fault unless the group itself killed it.

**Stdio and environment.** The child inherits stdout and stderr and the environment; stdin is `/dev/null` (inheriting it makes two processes race for the terminal). Working directory is inherited. An optional `environment` and working directory override are v1.1.

**Windows.** Spawn-same-exe works; what differs is the descriptor. `std::process::Command` cannot pass extra inheritable handles, so the plan is a named pipe (random name in `MS_FORK_IPC`, created by the parent with a DACL limited to the current user, connected by the child before running the entry) and the existing job object for lifetime. Because the Windows runtime is already built with limited coverage (`sys_windows.rs`), recommendation: Linux and macOS in the first stages; `fork` returns `Unsupported` on Windows until its stage lands. This is a documented limit, not a checker error.

**No shared memory in v1.** No mmap'd regions, atomics or locks; `Shared` is not sendable. Values cross by copy only.

## Alternatives

1. **Do nothing.** Agents use `Commands.spawn` with the program's own executable plus hand-rolled byte pipes. No code runs in a child with types, no scope lifetime for it, and every user reinvents framing. Cheapest; leaves multi-core use to hand-built plumbing.
2. **POSIX `fork()`.** Rejected: multithreaded runtime (lock and poller state), not portable, copies the whole heap implicitly and breaks "one owner" at the OS level. Safe only before any thread starts, which the runtime does not guarantee.
3. **Fork a closure.** Rejected: closures capture owned state that would have to be serialized; entry functions have only declared sendable inputs.
4. **Entry by string (`"module.ms", "main"`).** Possible (JS-style), but a typo is a runtime failure, the compiler cannot know which functions to keep or generate codecs for. Function items give both.
5. **JSON or self-describing format over stdio.** Rejected above; stdio also collides with the child's user-visible stdout.
6. **Wait for worker threads.** Tier 2 threads need per-thread runtime globals. Processes work today with no change to `ms-rt` globals, so they are the earlier route to cores and also give crash isolation threads cannot.

## Cost and risks

- Evidence of benefit is design-level. No measurement here shows a workload that gains; the first stage that runs code must record exec-plus-startup latency of a fork child and serialization throughput of a large `List[Int]` and a `Bytes` blob against a plain pipe, and the benefit claim stands or falls on it. Static musl binaries start fast but a large binary is re-exec'd per child.
- Compiler work: entry-table emission, per-type codec lowering (mirror of clone), the call-site checks (function item, signature, sendable). Runtime: start-path hook, socket framing, parent-death handling.
- Dependency: the `Sender`/`Receiver` types and `TaskGroup` (TaskGroup stages 3 and 4). Fork can start with its own endpoint types behind the same API, but the public names must come from TaskGroup stage 4 to avoid two channel types.
- Security: child inherits environment and the IPC socket only; descriptors are `CLOEXEC` except the one; the Windows pipe is user-restricted.
- Interaction with `ms test`: it already runs each test in its own invocation with a selector, so the entry selector must not collide (own env var, checked first).

## Stages (each its own PR, auto-merge)

1. Docs: this design in canonical pages, DESIGN.md/VISION/expert entry. Needs TaskGroup stage 1.
2. Sendable checker rule (shared with workers) and per-type codec with round-trip tests, plus the measurements above. No processes yet.
3. Entry table and start-path hook: run an exported function in a re-exec'd same executable with an argument and result frame, no channels.
4. IPC transport: socketpair framing, `Sender`/`Receiver` over it, backpressure, EOF, oversize and malformed frames, parent-death cancel.
5. `TaskGroup.fork` and `.process`: scope join/kill, fault surfacing, sibling kill.
6. Diagnostics (a lambda or method passed to `fork`, `os.fork()`/`child_process.fork` shapes pointing to `group.fork`) and cheat sheet.
7. Windows (named pipe plus job object).

## Open questions for the owner

- Function item (recommended) or string path as the entry.
- Compact type-directed binary (recommended) or JSON.
- v1 processes pass only the two entry endpoints (recommended) or also allow channels inside messages.
- Windows deferred (recommended) or in the first release.
- Child stdin `/dev/null` (recommended) or inherited.
