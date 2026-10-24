# Child processes and `fork` (design proposal)

## Summary

- Problem: a program uses one core, and cannot run Manuscript code in another long-lived process that it talks to with typed messages.
- Change: `ProcessGroup` in `@std/processes.ms` starts a child process (a re-exec of the same binary) at a named top-level `def`. The child is a long-lived peer: the parent and child exchange typed messages in both directions over one bidirectional channel. Messages are JSON over a dedicated IPC channel (not stdio).
- A `Process[In, Out]` is the typed sibling of `Subprocess`: same lifecycle (`wait`, `terminate`, `kill`, `close`), same `Stdio` choice per stream, plus `send`, `receive` and `close_input`. The child's entry takes the other end of the same channel. There is no result type and no `T` on the group.
- `fork` is JS `child_process.fork`, not POSIX `fork(2)`: spawn the same binary, select an entry, connect a channel. No parent state is copied.
- Cost: an entry table, a start-path hook, an IPC-backed channel endpoint in the runtime, and a stdlib module. No new compiler codecs, no change to runtime globals (unlike `proposals/worker-threads.md`).
- Approved (Chinmay, 2026-10-24) with the recommended answers to the open questions; the endpoint type follows the bidirectional channel proposal.

## Status

- Approved; stages 2 and 3 implemented. The built shape follows `proposals/channels.md` and supersedes the API and frame sections below where they differ:
  - `ProcessGroup[T, In = Unit, Out = Unit]`, `spawn(entry, stdin, stdout, stderr) -> Result[Process[T, In, Out], CommandError]`; the entry is `def f(ch: Channel[Out, In]) -> T` with no separate argument; `Process.channel` is the parent's end, `result()` gives `T` or `ProcessError` (`Exited(status)`, `Broken`), `close()` closes the channel, then stops and joins the child.
  - No entry table: `MS_ENTRY` carries the code and drop words of the runner closure and the entry it captures, as offsets from `msrt_start` (`crates/ms-rt/src/start.rs`). The checker requires the entry to name a top-level `def`, since only a closure without captures can be rebuilt.
  - Frames are a 4-byte LE length, a kind byte (message, close, result) and a JSON body holding `{"value": ...}`, so `Unit` crosses (decoding restores an absent `Unit` member). Written in Manuscript in `stdlib/processes.ms`; Rust only makes the pipe and moves bytes (`crates/ms-std-process/src/fork.rs`, `ipc.rs`).
  - The IPC pipe is a socketpair on Unix and an overlapped owner-only named pipe on Windows registered with the runtime poller, so neither polls. `Stdio.Pipe` for a process is not offered yet (`InvalidInput`).
- Direction (Chinmay, 2026-10-24): `worker_threads`-style model extended to processes, with fork; separate proposal from threads; all platforms in the first release; no "sendable" concept; JSON if raw memory cannot work; dedicated group type; IPC must not use stdio or a TCP port (JS style); child streams forwarded to the parent's and configurable independently; the design must be more coherent than Node; processes are long-lived and talk over channels, so a `Child[T]` result type is wrong; `Process` has `send` and `receive` directly rather than `to_child`/`from_child` fields; channels are bidirectional, so the entry takes one channel end rather than a `Receiver` and a `Sender` (bidirectional channels are a separate proposal).
- Siblings: `proposals/taskgroup.md` (scope, channels), `proposals/worker-threads.md`, and the bidirectional channel proposal (separate thread). This proposal writes the child's end as `Channel[Send, Receive]` (sends `Send`, receives `Receive`); it adopts whatever spelling that proposal settles. The worker proposal still has a result-returning `WorkerGroup[T]`; the same objection (workers are long-lived too) probably applies there. Raised with the coordinator, not changed here.
- Reviews: four independent subagent reviews (see Review outcome).

## Problem

- One runtime thread runs all Manuscript code (`crates/DESIGN.md` decision 4); CPU-bound work cannot use more cores.
- Threads need per-isolate runtime state (`proposals/worker-threads.md`: 55 `Global<` uses, generated-code TLS). Processes need none of it.
- A faulting child exits without touching the parent's heap; threads cannot offer that.
- Typical uses are long-lived: a worker serving requests, a supervised helper, a pipeline stage. They need messages both ways, not a single return value.
- Today `Commands.spawn` (`stdlib/process.ms:62`) starts a program for use with `with` (closing it kills the process group) and gives byte pipes. A user can re-exec `info().executable` with an `args()` marker and exchange `stringify`/`parse` text over stdio by hand. What they lack:
  - a function item as the entry instead of a hand-written argv convention;
  - typed messages in both directions without writing framing, and without taking over the child's stdout;
  - one lifecycle shape shared with the other groups.
- Not measured: no benchmark here shows a workload that gains. Stage 1 must record start latency, message round-trip latency and throughput.

## Goals and non-goals

- Goals:
  - one model for starting, talking to and stopping a child: the same `with`, `Stdio` and channels as elsewhere;
  - child stopped when the scope exits, so no child outlives its `with`;
  - child death observable as data (exit status), not a parent fault;
  - Linux, macOS and Windows.
- Non-goals:
  - POSIX `fork()` or any copy of parent state;
  - shared memory;
  - sending handles, closures or `Shared` values in messages;
  - more than one channel per process in v1;
  - changing single-process behavior.

## Design

### Syntax and API

```manuscript
from "@std/processes.ms" import ProcessGroup
from "@std/tasks.ms" import Channel

type HashConfig:
    algorithm: String

def hasher(parent: Channel[String, Bytes], argument: HashConfig):
    while True:
        if let chunk = parent.receive():
            parent.send(digest(argument.algorithm, chunk))
        else:
            break

def hash_all(chunks: List[Bytes]) -> List[String]:
    var digests = List[String]()
    with ProcessGroup() as group:
        let worker = group.spawn(hasher, HashConfig(algorithm="sha256"))
        for chunk in chunks:
            worker.send(chunk.clone())
            if let digest = worker.receive():
                digests.append(digest)
        worker.close_input()
        worker.wait()
    return digests
```

Illustrative: `digest` is a placeholder; `if let` is the documented unwrap (`documentation/core-language/control-flow/conditionals.md:58`); `receive() -> Optional[T]` follows `proposals/taskgroup.md:43`. The parent sends one request and reads one reply per iteration, so neither side blocks on a full buffer. A producer that sends many messages before reading replies must run its sends and receives in different tasks, because both directions are bounded.

- `ProcessGroup`: `Closeable`, no type parameter. `close()` stops every still-running child (cancel, grace period, kill) and joins it.
- `spawn(entry, argument, stdin: Stdio = Stdio.Inherit, stdout: Stdio = Stdio.Inherit, stderr: Stdio = Stdio.Inherit) -> Process[In, Out]`.
  - `entry` is a named top-level `export def f(parent: Channel[Out, In], argument: A)`, from any module; `proposals/worker-threads.md:188` uses a `Receiver` and `Sender` pair and should move to one channel end too; one binary, so a function item identifies it, with no path string.
  - The entry returns when its work is done; returning is a normal exit (status 0).
- `Process[In, Out]`:
  - `send(value: In)`, `receive() -> Optional[Out]`, `close_input()`: the parent's end of the channel, with the transport being the IPC connection. `close_input()` closes the parent-to-child direction; `close()` keeps its `Subprocess` meaning (stop the process).
  - `wait(timeout: Optional[Duration] = none) -> Result[Int, CommandError]`: the exit status, as `Subprocess.wait` (`stdlib/process.ms:69`). A nonzero status is data.
  - `terminate()`, `kill()`, `close()`: as `Subprocess`.
- `Stdio`: `Inherit` (default: the child gets the parent's descriptor, so logs go wherever the parent's go), `Null`. `Pipe` (returns the stream on `Process`, as `Subprocess` does) is deferred.
- Rejected at the call site (illustrative text): `spawn(lambda: serve(x), 1)` -> "process entry must be a named top-level def taking (Channel, argument); lambdas and captures cannot run in another process".
- `A`, `In`, `Out` need a JSON form; types without one are rejected at the call (decision 4).

### Semantics

- Start: the parent creates the IPC channel, then runs `info().executable` through `Commands.spawn`'s start path (`crates/ms-std-process/src/spawn.rs:61`) with env `MS_ENTRY=<index>` and `MS_IPC=<fd or pipe name>`; stdin, stdout and stderr follow the `Stdio` arguments.
- Start hook: `msrt_start` (`crates/ms-rt/src/start.rs:263`) checks `MS_ENTRY` before `main`. If set, it clears both variables from the environment seen by user code, adopts the IPC endpoint, reads the argument frame, and runs the entry as the main task. User `print` and stdio are untouched.
- Entry table: each `spawn` instantiation registers `(index, thunk)`. The thunk is generic Manuscript in `@std/processes.ms`: `parse[A]` the argument, bind the IPC-backed `Channel[Out, In]`, call the entry. Lowering instantiates generics per type argument list (`crates/ms-lower/src/lib.rs:4-5`), so the existing `stringify`/`parse` intrinsics (`ms-lower/src/native.rs:208`, `json.rs`) need no new codec code. The table is an index, not a hash: parent and child are one binary.
- IPC channel (JS style, as Node's `NODE_CHANNEL_FD`; no TCP port):
  - Unix (Linux and macOS): `socketpair(AF_UNIX, SOCK_STREAM)`; the parent keeps one end `CLOEXEC`, the other is `dup2`'d to a fixed descriptor in `pre_exec` (async-signal-safe, so sound in a multithreaded parent) and its number is `MS_IPC`. Both ends are nonblocking and wait in the existing poller (epoll, kqueue).
  - Windows: the parent creates a named pipe with a random name (`\\.\pipe\ms-ipc-<random>`, first-instance flag, DACL limited to the current user, one accepted connection) and puts the name in `MS_IPC`; the child opens it by name, so no handle inheritance or handle list is needed. The Windows poller waits on sockets only and counts other handles as ready at once (`poller.rs:210-215`), so pipe waits use the same slice polling `Subprocess` already uses: `PeekNamedPipe` in 2 ms slices (`crates/ms-std-process/src/plat/windows.rs:20`, `wait_io` at `:33`).
  - One framing layer sits over both transports.
  - Descriptor rules: the parent closes its copy of the child's end right after spawn (otherwise it holds both ends and never sees EOF when the child dies); the child sets `CLOEXEC` on the inherited descriptor when it adopts it, so its own children do not keep the socket open; when the entry returns the runtime flushes pending outbound frames and the `close` frame before exiting.
- Frames: a 4-byte little-endian length, a 1-byte kind, then UTF-8 JSON. Kinds: `argument`, `message`, `close` (end of one direction's channel). A channel id is added with more than one channel (stage 4).
- Backpressure: each direction has a bounded buffer of `capacity` messages (default 64, a `spawn` parameter `capacity: Int = 64`). The runtime reads the IPC connection into the receiving endpoint's buffer only while it has room; when full it stops reading, the OS buffer fills, and the peer's `send` waits. Two peers that both block in `send` deadlock, as with any bounded channels; the example avoids it by alternating, and cancellation still breaks it.
- Channel semantics follow `proposals/taskgroup.md:41-45`:
  - `send` consumes the value and waits when the pipe or the peer's buffer is full; it is a cancellation point;
  - `receive` returns an owned value, or `none` once the peer has closed its sender and the buffer is empty;
  - `close_input()` delivers end-of-input; the child's `receive` then returns `none`. The child closes its sending direction by returning from the entry or with the channel end's close. `proposals/taskgroup.md:44` closes a channel only by dropping the last sender; the bidirectional channel proposal must provide an explicit close of one direction;
  - a leaked sender (the capture-drop gap, `proposals/taskgroup.md:49`) delays end-of-input but not the stop path, which uses connection EOF;
  - `send` after the peer is gone returns a closed result (final shape decided with TaskGroup stage 4).
- Transfer: JSON, not raw memory.
  - Strings, lists, maps and records hold heap pointers, and `Map`/`Set` carry a hash index, so only plain-bits values (`KIND_POD`, `crates/ms-rt-abi/src/lib.rs:343`) could be copied as bytes.
  - `TypeDesc` (`lib.rs:367`) has no field layout for records and alternatives (`KIND_CUSTOM`, `lib.rs:351`), so a binary codec is new compiler work.
  - Supported: records, alternatives, `Optional`, `Result`, `List`/`Set`/`Map`, `Bytes` (base64), `Int`, `BigInt`, `Decimal`.
  - What JSON does with a no-form value (`stdlib/json.ms:~119-122`): a record field is omitted, a list element becomes `null`, a map value is omitted, a root returns `InvalidData`. A `Listener` in a record is rejected at the call site (decision 4).
  - `JsonEncode.to_json` types encode custom but cannot decode (`json.ms:~88-90`), so they cannot cross.
  - Losses documented, not patched: `NaN` and infinities become `null`; `Map` keys limited to JSON's key types.
- Stop:
  - `close()` (leaving the block, parent cancel, signal) closes the IPC connection. The child runtime treats connection EOF as cancellation of its main task, so shielded cleanups run; after a grace period (default 5 s) the child's process group is killed (`SIGKILL`, as `Subprocess.stop`, `command.rs:271-276`) and joined.
  - `terminate()` and `kill()` act on the child's process group as for `Subprocess`.
  - Unix children run in their own process group (`spawn.rs:86`); Windows uses `CREATE_NEW_PROCESS_GROUP` (`spawn.rs:92`) plus a job object.
- Orphans: a parent killed without cleanup closes the connection (the OS closes the socket end or pipe handle); the child sees EOF and cancels. Same path as `close`.
- Death is data:
  - A child fault runs its cleanups, writes the fault text to its stderr, and exits 70. `wait()` returns 70; `receive()` returns `none`; `send` returns closed. The parent keeps running.
  - A child killed by a signal reports -1, as `Subprocess.wait`.
  - This differs from `TaskGroup` v1 (a child fault ends the process), because crash isolation is the reason to use a process and `Commands` already treats exit status as data. Decision 2.
- Waiting for exit: pidfd on Linux (`spawn.rs:136`); elsewhere slice polling (`command.rs:5-17`).
- Environment and working directory are inherited.

```mermaid
sequenceDiagram
  participant P as parent
  participant C as child (same exe)
  P->>C: exec info().executable, env MS_ENTRY, MS_IPC
  P->>C: argument frame
  P-->>C: message frames (Process.send)
  C-->>P: message frames (child channel send)
  P->>C: close frame (end of input)
  C->>P: close frame, exit 0
  P->>C: on group close: IPC EOF (cancel), kill after grace
```

### Platform parts

- Executable path: `ProcessControl.info().executable` (`stdlib/process.ms:121`).
- Windows job object: assigned after spawn today (`spawn.rs:118-125`), racy and without `KILL_ON_JOB_CLOSE`; must be assigned at creation and kill on close so grandchildren die with the child.

## Components touched

| Component | Change | Risk / test |
| --- | --- | --- |
| `crates/ms-check` | process entry rule: named top-level def `(Channel[Out, In], A)`, diagnostics | conformance reject cases |
| `crates/ms-lower`, `ms-mir`, `ms-clif` | entry table: each `spawn` instantiation registers `(index, thunk)`; no new codecs | e2e fixture on 3 platforms |
| `crates/ms-rt` | start hook for `MS_ENTRY`; IPC-backed channel end (a second transport for the bidirectional channel: parked-waiter token per direction, framing, close); connection-EOF cancel | cancel, EOF, backpressure, malformed-frame tests |
| `crates/ms-std-process` | `spawn::start` gains env, per-stream inherit/null modes (today three pipe descriptors only, `spawn.rs:61`) and an extra inherited descriptor; socketpair with `pre_exec` on Unix, named pipe on Windows; job object at creation with `KILL_ON_JOB_CLOSE` | per-crate tests incl. Windows |
| `stdlib/processes.ms`, `bindings.json` | `ProcessGroup`, `Process`, `Stdio`, entry thunk in Manuscript | `make docs`, extern parity |
| `stdlib/process.ms` | unchanged in stage 3; sharing `Stdio` with `Commands.spawn` (decision 1) is its own stage | - |
| `crates/ms-std-json` | unchanged | round-trip tests for supported types |
| `ms-syntax`, formatter, lint, LSP | unchanged (no syntax) | - |
| Docs | core-language page, cheat sheet (`ms guide`), `crates/DESIGN.md` decision 4, `VISION.md`, `.experts/runtime.md`, `proposals/taskgroup.md` (drop `spawn_worker` string form and sendable text; line 65 still scopes processes in a `TaskGroup`) | `make repo-check`, `make book-check` |
| Conformance | start, ping-pong, backpressure, close and EOF, cancel, child death as data, JSON edge values | `make conform` |

## Examples

- End-to-end: `hash_all` above, run over 100 MB of chunks in stage 1.
- Supervised helper: the parent starts a `Process`, sends requests as they arrive, and `with` stops the helper at scope exit; if the helper dies, `receive()` returns `none` and the parent can respawn it.
- Manual recipe (works today, the do-nothing baseline; illustrative, not run): re-exec `executable_path()` with a `--child` marker through `commands.spawn`, write `stringify(request)` lines to the child's stdin and read `parse` lines from its stdout. The child's own prints would corrupt the channel, and typed lifecycle is hand-written.
- Rejected (illustrative, decision 4): `group.spawn(serve, listener)` with `listener: Listener` -> "process argument cannot be sent: `Listener` has no JSON form".

## Alternatives

- Do nothing, and document the manual recipe: gives typed JSON, scoped kill through `with` and a result over stdio on all three platforms. Lost: an entry that is a function item, typed messages in both directions without owning the child's stdout, lifecycle shared with the other groups.
- A result-returning `Child[T]` with `results()`: rejected by the owner; processes are long-lived and talk over channels.
- Smallest version: one process, one channel, no `Stdio` choice beyond inherit. This proposal's v1 keeps the channel and `Stdio`, because inherit-by-default and no stdout takeover are the points.
- Frames on the child's stdin and stdout: rejected by the owner. A child's own writes to descriptor 1 would corrupt frames.
- Loopback TCP socket with a token: rejected by the owner (no port).
- POSIX `fork()`: rejected; the runtime is multithreaded (a blocking pool; `fork()` keeps one thread and inherits held locks, the poller and coroutine stacks), unavailable on Windows, and breaks single ownership at OS level.
- Raw memory transfer: rejected; heap pointers and the map hash index (see Semantics). Only plain-bits values qualify.
- New binary codec: deferred; new compiler work (`TypeDesc` lacks record layout). Revisit only if stage 1 shows JSON is the bottleneck.
- Entry by path string: rejected; typo is a runtime failure and the compiler cannot know which functions to keep.
- Fork a closure: rejected; captured owned state would need encoding.
- Methods on `TaskGroup`: rejected by the owner; a dedicated group names what it scopes.
- Wait for worker threads: threads need the isolate refactor first (`proposals/worker-threads.md`); processes need none of it and add crash isolation.
- Table hash handshake, cancel frame: cut; one binary, and connection EOF is the cancel signal.

## Drawbacks

- Process start cost per child (exec of the whole binary), and JSON encode/decode and a socket hop per message; all unmeasured.
- An IPC-backed channel endpoint is real runtime work, a second implementation of the channel endpoint beside the in-process one.
- Two transports (Unix socketpair, Windows named pipe) under one framing layer; Windows waits on the pipe in 2 ms slices, not by readiness.
- The call-site JSON check is new checker work.
- Depends on bidirectional channels (separate proposal) and TaskGroup stage 4; until they land only stages 1 and 2 can be built.
- A third group type beside `TaskGroup` and `WorkerGroup`; learners hold three.

## Prior art

- JavaScript `child_process.fork`: same-executable spawn with a dedicated IPC channel and `send`/`message`. Differs: function item entry, typed bidirectional channel instead of untyped `send`, scoped group, `Stdio` shared by name with the rest, exit status as data.
- Python `multiprocessing`: spawn start method, `Pipe`/`Queue`, pickled objects. Differs: JSON, no closures.
- Erlang processes: long-lived, mailbox, links. Differs: OS processes, typed channels.
- Go `os/exec` plus self-exec: manual; the do-nothing baseline.
- Rust `std::process::Command` with `current_exe`: same technique, untyped.

## Evidence and cost

- Verified in source: `spawn::start` takes only three stdio descriptors and sets a process group (`spawn.rs:61-92`); `Subprocess.wait`, `terminate`, `kill`, `close` exist (`stdlib/process.ms:69`); pipes park on pidfd on Linux and poll in slices elsewhere (`command.rs:5-17`), including `PeekNamedPipe` on Windows (`plat/windows.rs:20`, `wait_io` at `:33`); the Windows poller waits on sockets only (`poller.rs:210-215`); `msrt_start` has no pre-`main` dispatch (`start.rs:263`); typed `stringify`/`parse` exist (`json.ms:78,153`) and generics are instantiated per type argument list (`ms-lower/src/lib.rs:4-5`); the executable path is exposed (`process.ms:121`); pull requests run Linux only, other platforms on main, merge groups and manual runs (`.github/workflows/cicd.yml:55-57`).
- Not measured: child start latency, message round-trip latency, JSON throughput over a socketpair and a named pipe, 2 ms slice latency on Windows.
- Adds: one stdlib module, an entry table, one runtime start path, an IPC channel endpoint, one checker rule. Learner concepts: `ProcessGroup`, `Process`, `Stdio`.

## Staging and verification

- Each stage is its own PR with auto-merge. Pull requests run Linux only; for any stage touching platform code, run the workflow by hand on the branch for macOS and Windows before merging.
1. Measure with a throwaway spike branch (nothing merged to main; `@std/processes.ms` and `@std/tasks.ms` do not exist yet, so this uses Rust micro-benchmarks and a hand-written `Commands.spawn` program): re-exec latency, JSON throughput for `List[Int]` and `Bytes`, and ping-pong round-trip latency through a socketpair (Unix) and a named pipe (Windows, manual run), against the manual recipe. Go/no-go (proposed, Chinmay confirms): start latency under 50 ms and round trip under 1 ms on Unix; otherwise document the recipe and stop.
2. Platform prerequisites: job object at creation with `KILL_ON_JOB_CLOSE`; `spawn::start` env, per-stream `Stdio`, extra descriptor; socketpair and named pipe plumbing with tests.
3. `ProcessGroup.spawn` and `Process`: entry table and start hook, IPC-backed channel endpoints, frames, argument, stop and orphan paths, death as data, diagnostics, docs and cheat sheet, conformance. Needs bidirectional channels and TaskGroup stage 4 landed.
4. Extensions as demand shows: `Stdio.Pipe`, more than one channel (channel ends in arguments, a channel id in the frame), environment and working-directory overrides.

## Open questions

- Decided (Chinmay, 2026-10-24, recommended answers accepted):
  1. One `Stdio` type (`Inherit`, `Null`, `Pipe`) and one lifecycle shape shared by `Commands.spawn` and `ProcessGroup.spawn`; this changes the existing `Commands` API.
  2. Child death is data; the parent survives.
  3. Leaving the `with` block stops running children.
  4. Types with no JSON form (resource, closure, `Shared`, handle) are rejected at the call site as an ordinary type error, the same boundary check `proposals/worker-threads.md` uses; no user-visible concept.
  5. One channel per process in v1.
  6. `Process` has `send`, `receive`, `close_input` directly; the entry takes one bidirectional channel end.
- Resolve during implementation:
  - Windows named pipe by name (recommended) or an anonymous pipe passed by inherited handle (needs a handle list in `CreateProcess`).
  - Grace period default (proposed 5 s) and whether it is a parameter.
  - Whether connection EOF cancellation needs a poll hook on the child's main task.
  - Final shape of `send` to a closed peer (with the bidirectional channel proposal).

## Rejected ideas

- A `Sendable` trait or rule (owner: avoid).
- A typed result and `results()` for processes (owner: long-lived, channels).
- Methods on `TaskGroup` (owner: dedicated group).
- Linux-only first release (owner: all platforms).
- Raw memory transfer (not sound across processes; see Semantics).
- Frames on stdin and stdout, and a TCP port (owner; see Alternatives).

## Future possibilities

- `Stdio.Pipe` and more channels per process.
- Binary frame body if JSON is measured as the bottleneck.
- A matching long-lived shape for `WorkerGroup`.

## Review outcome

- First review (against source): group kill is `SIGKILL`, so cleanup needs a cooperative stop; the Windows job object is assigned after spawn and lacks `KILL_ON_JOB_CLOSE`; there is no per-type clone to mirror, so a binary codec is new work; `spawn::start` has no extra-descriptor support.
- Second review (all `file:line` citations verified): JSON omits no-form fields rather than faulting; `PDEATHSIG` fires on spawning-thread exit and was dropped; names aligned with the worker proposal; pull requests run Linux only.
- Third review (simplification): cut the table hash, the cancel frame, per-entry codecs and four stages; a generic stdlib thunk reuses `stringify`/`parse`.
- Owner direction after the third review: no stdio or TCP transport (JS-style dedicated channel); independent `Stdio` per stream; processes are long-lived peers with channels in both directions, so `Child[T]`, `results()`, `spawn`/`fork` as two methods and the group's type parameter were removed, and child death became data.
- Fourth review (of the channel redesign), folded in:
  - the example did not type check (`while let some(...)`) and deadlocked (sent all chunks before reading); rewritten with the documented `if let` and one request and reply per iteration, with backpressure rules stated;
  - `Sender.close()` is not in `proposals/taskgroup.md`; added as a requirement, with last-clone and leaked-sender behavior;
  - entry shape aligned with `proposals/worker-threads.md:188`; spelling difference of `Channel`/`channel` noted;
  - descriptor rules added (parent closes the child's end, child sets `CLOEXEC`, flush on exit);
  - citations corrected; `pid()`, `ProcessGroup.wait()` and the frame channel id cut;
  - stage 1 is a throwaway spike, since the stdlib modules do not exist yet.
- Owner direction after the fourth review: `send`/`receive` on `Process` instead of `to_child`/`from_child`; bidirectional channels (separate proposal), so the entry takes one channel end; open questions resolved with the recommended answers.
