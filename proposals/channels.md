# Channel: one bidirectional endpoint for tasks, workers and processes (design proposal)

## Summary

- Problem: `proposals/taskgroup.md` stage 4 plans `channel[T]() -> (Sender[T], Receiver[T])`; `proposals/child-processes.md` stage 3 plans `fork` with an entry `def f(input: Receiver[In], output: Sender[Out], argument: A)`. That is two endpoint types, two entry parameters, and a pair of channels per conversation.
- Change: one type, `Channel[Send, Receive]`. An endpoint both sends `Send` and receives `Receive`. A pair is `Channel[A, B](capacity)`, which creates a connected pair and returns one end; `ch.peer()` takes the other end, `Channel[B, A]`, once. The two ends have the type arguments swapped.
- Entry rule: a worker or process entry takes **one** parameter, the child's end of the channel: `def f(ch: Channel[In, Out]) -> R`. `spawn(entry)` creates the pair, passes one end, returns the other.
- Transport follows where the peer lives: queue between tasks, moved values between workers, JSON frames between processes. The API is identical.
- Cost: no new syntax; one runtime endpoint type; deletes `Sender`, `Receiver` and the `clone` fan-in from the TaskGroup plan. Decision requested: sign-off on the type shape, the entry rule, and the open questions below.

## Status

- Proposal, 2026-10-24, written against `main` at `6361798f`. Nothing implemented. No `ms` binary was built; all `.ms` below is illustrative.
- Direction (Chinmay, 2026-10-24): "channels should be bidirectional"; "can the entry take in a Channel directly? why two args"; "our design needs to be more coherent than node"; `Channel` stays uppercase.
- Review: one skeptical subagent review done; folded in below (see Review outcome). Awaiting Chinmay's sign-off.

## Problem

- `Sender[T]`/`Receiver[T]` are one-way. Two-way conversation (request/response, a worker that streams results and takes commands, a child process with IPC) needs two pairs, four endpoints, and two parameters on every entry.
- `proposals/child-processes.md` needs a different type each way (e.g. `Bytes` parent to child, `String` child to parent), so a single `Channel[T]` is not enough either.
- Node's split (`worker.postMessage` + `on('message')`, `process.send` + `on('message')`, separate `MessageChannel` ports, an `argv`/`workerData` side door) is the incoherence to avoid: three places a message can enter a child.
- Affected: stdlib authors of `@std/tasks.ms`, `@std/workers.ms`, `@std/processes.ms`; users writing concurrent programs; agents reading the guide.

## Goals and non-goals

- Goals:
  - one endpoint type across `TaskGroup`, `WorkerGroup` and `ProcessGroup`;
  - independent message type per direction;
  - a child entry has one input: its channel;
  - `receive()` returns `none` once the peer is closed and the buffer is drained;
  - Linux, macOS and Windows at parity; no platform-gated test.
- Non-goals:
  - `select` over channels, timeouts on `receive`, iteration (`for m in ch`) until `stdlib/streams.ms` is checked;
  - multi-producer fan-in and endpoint cloning (see Rejected);
  - sending channel endpoints inside messages (no descriptor passing; shared with `proposals/child-processes.md`);
  - implementing TaskGroup, workers or processes themselves.

## Design

### Syntax / API (`@std/channels.ms`, re-exported by the group modules)

```manuscript
from "@std/channels.ms" import Channel

# Channel[Send, Receive]
Channel[A, B](capacity: Int) -> Channel[A, B]   # constructor: creates a connected pair, returns one end
ch.peer() -> Channel[B, A]                       # takes the other end; a second call faults

ch.send(value: Send) -> Result[Unit, Closed]   # consumes value; parks while full; cancellation point
ch.receive() -> Optional[Receive]              # owned value; none when peer closed and drained; parks while empty
ch.close() -> Unit                              # Closeable; idempotent; drop does the same
```

- The two ends of a pair are symmetric: what one sends the other receives. Mnemonic: `Channel[Send, Receive]` reads from the holder's side.
- One-way use is the same type with the unused direction ignored: `Channel[Job, Unit]` and its peer `Channel[Unit, Job]`. No second type, no `Never`.
- Same-type duplex is `Channel[T, T]`.

Entry rule for all three groups:

```manuscript
from "@std/workers.ms" import WorkerGroup
from "@std/channels.ms" import Channel

record Frame:
    id: Int
    pixels: Bytes

def render(ch: Channel[String, Frame]) -> Int:   # child end: receives Frame, sends String
    var count = 0
    while true:
        guard let frame = ch.receive() else:
            break
        count += 1
        ch.send("done {frame.id}")
    return count

def run(frames: List[Frame]) -> Result[Int, TaskError]:
    with WorkerGroup[Int]() as group:
        var ch = group.spawn(render)            # parent end: Channel[Frame, String]
        for frame in frames:
            ch.send(frame)
        ch.close()                              # child's receive() returns none
        return group.results()                  # sum or list per group contract
```

- `spawn(entry)` accepts `entry: def(Channel[S, R]) -> T` and returns `Channel[R, S]` (the parent end). The pair is created by `spawn`, so its transport is chosen by the group.
- The same call on `ProcessGroup` or `TaskGroup` compiles unchanged; only the import differs. For `TaskGroup`, `entry` may also be a lambda that captures its end: `group.spawn(lambda: pump(ch_child))` with `Channel[A, B](n)` and `peer()` called in the parent.
- No argument form: the entry's only input is its channel; initial data is the first message (a record or alternative if several values are needed). This removes the "channel or plain argument" overload from `spawn` and the second input path.
- Checker shape: an explicit `spawn[S, R](entry: def(Channel[S, R]) -> T) -> Channel[R, S]` on a concrete generic group. Whether the checker can infer `S`, `R` from a function item is unproven; stage 0 is a spike.
- Bindings that call `close()` must be `var` (`Closeable.close` is `var def`, `stdlib/core.ms:64`); examples use `var ch`.

### Semantics

- Ownership: `send` consumes its argument (moves it into the queue); `receive` returns an owned value. Each end is move-only, so one owner per end.
- Close, per direction:
  - `ch.close()` or dropping `ch` closes the whole conversation from that side. The peer's `receive()` drains what is buffered, then returns `none`. The peer's `send` returns `Closed` (the unsent value is dropped).
  - Entry return drops the child's end, so the parent sees `none` when the child finishes.
- No half-close in v1: a side that is done sending but still receiving keeps sending a final message and waits for the peer to close (a protocol, not a primitive). See open question 3.
- Capacity: `capacity >= 1` bounds each direction between tasks and workers. Over processes it is not enforced (that needs credit-based flow control); the sender parks when the OS socket buffer is full. Rendezvous (`0`) is not offered in v1.
- Cancellation: `send` and `receive` are cancellation points. A cancelled `receive` unwinds the task; its end is dropped, so the peer sees close.
- Fault (v1): inherits TaskGroup's abort rule. No channel-specific fault path.
- Leak: captures of a cancelled or faulted task are not dropped today (`proposals/taskgroup.md:49`), so a cancelled task's end is NOT dropped and the peer's `receive()` can park forever. Stage 2 is conditional on the capture-drop fix (run drops on the guard exit).
- Deadlocks: a task holding both ends, or two peers that both `send` first on a full channel, park forever. `crates/ms-rt/src/task.rs:611` faults only when every task is parked. No diagnostic is added in v1; a fixture pins the fault. No `select` or timeout exists to break mutual sends.
- Unused direction: a `Channel[Job, Unit]` holder can still call `receive` and park. This is convention only; the real cost of bidirectional endpoints.
- Child exit: a child returning early closes the parent's `send` (`Closed`) and drops queued unread parent messages; the parent learns only through `Closed`/`none` and `results()`.
- Crash: "drop sends the marker" does not cover a crashed or SIGKILLed child. For processes, EOF on the IPC connection is also close, and `results()` reports the exit status.
- Payload types crossing a worker boundary follow `proposals/worker-threads.md` (no `Resource`, `Shared`, closures, `ref`); across a process boundary the type must also be JSON round-trippable (`proposals/child-processes.md`). Both are ordinary type errors on `spawn`, reported on the entry's channel parameter type.

### Transport by endpoint location

| Peer location | Created by | Transport | Backpressure |
| --- | --- | --- | --- |
| Same thread (tasks) | `Channel[A, B](n)` + `peer()` | in-runtime queue, value moved | park on full/empty via task tokens |
| Other thread | `WorkerGroup.spawn` | bounded mutex queue, value moved (no copy, no codec); needs the per-thread runtime of `worker-threads.md`, so not before it | park on target isolate's wake fd |
| Other process | `ProcessGroup.spawn` | length-prefixed JSON frames on the IPC connection, frame carries a close marker | OS socket buffer only |

- `Channel(n)` and `peer()` are only for peers on the same thread. A worker or process end cannot be built by hand; this keeps transport selection out of user code and means one pair is never split across locations.
- IPC frame (processes): 4-byte little-endian length, UTF-8 JSON of the message; a zero-length frame is the close marker. One channel per child, so no channel id (the earlier "channel id" in `child-processes.md` stage 3 is deleted).

## Components touched

| Component | Change | Risk / test |
| --- | --- | --- |
| `stdlib/channels.ms` (new) | `Channel[S, R]`, constructor, `peer`, `send`, `receive`, `close`; `Closed`. Externs are not generic and `extern type` is "planned, not shipped" (`skills/runtime/SKILL.md:18`): either a generic runtime-owned type with per-`T` drop/move through `TypeDesc`, or `Channel` written in Manuscript over a non-generic byte-queue extern (decided by the stage 0 spike) | conformance: order, close, drain, closed send |
| `crates/ms-rt` | refcounted endpoint pair, waiter tokens, close flags; no sender-count (each end is single owner) | runtime unit tests; cancel while parked |
| `crates/ms-check` | worker/process boundary payload check on `spawn`; `spawn` accepts a `Channel`-parameter entry | reject cases: `Shared`, closure payload |
| `crates/ms-lower`, codegen | depends on the stage 0 choice; unknown until the spike | spike result recorded here |
| `stdlib/tasks.ms`, `workers.ms`, `processes.ms` | `spawn(entry)` returns the parent end | per-group fixture, same test body in all three |
| `proposals/taskgroup.md` | stage 4: replace `channel[T]`, `Sender`, `Receiver`, `clone` with `Channel` | edited on approval (avoids conflict with PR #1166) |
| `proposals/child-processes.md` | `fork` removed; `spawn(entry)` with a channel entry replaces it; no channel id | edited on approval |
| `proposals/worker-threads.md` | stage 4 and open question on entry shape resolved | edited on approval |
| formatter, lint, LSP, VS Code | unchanged (ordinary generic type and methods) | symbol search shows `Channel` |
| `documentation/core-language/` | one concurrency page section, `ms guide` cheat-sheet entry | docs build |
| CLI | unchanged | none |

## Examples

Task pair with different types each way (illustrative):

```manuscript
from "@std/tasks.ms" import TaskGroup
from "@std/channels.ms" import Channel

def squares() -> List[Int]:
    var mine = Channel[Int, Int](4)
    var theirs = mine.peer()
    with TaskGroup[Unit]() as group:
        group.spawn(lambda: serve(theirs))
        var out: List[Int] = []
        for n in range(5):
            mine.send(n)
            guard let sq = mine.receive() else:
                break
            out.append(sq)
        mine.close()
        group.wait()
        return out

def serve(ch: Channel[Int, Int]) -> Unit:
    while true:
        guard let n = ch.receive() else:
            return
        ch.send(n * n)
```

Rejected: a channel payload that cannot cross a worker (illustrative text):

```manuscript
def bad(ch: Channel[Shared[Int], Int]) -> Unit:
    return

with WorkerGroup[Unit]() as group:
    group.spawn(bad)    # error: worker channel payload Shared[Int] cannot cross a thread
```

## Alternatives

- **Do nothing / keep `Sender`+`Receiver`.** Cheapest; TaskGroup stage 4 is already written. Costs: two endpoint types, entries take two channel parameters, request/response needs two pairs. Process IPC still needs different types per direction, which one-way endpoints express as two channels per child.
- **`Port[Send, Receive]` placeholder name.** Same shape; `Channel` is the owner's name.
- **`Channel[T]` same type both ways.** Smaller, but a process child that receives `Bytes` and replies `String` would need a wrapping alternative on both sides. Rejected on child-processes evidence.
- **Pair-returning function or static method.** Rejected: the language has no tuples (`documentation/core-language/basics/expressions.md:158`), no `let (a, b)` pattern (`types/destructuring.md`), no static methods (`types/contracts.md:76`), and Chinmay keeps `Channel` uppercase (no lowercase `channel(...)`). A record result (`ChannelPair`) needs a non-literal constructor and field destructuring of move-only values; unverified.
- **`peer()` that faults on the second call.** The cost of one-constructor-two-ends; the alternative is `peer()` returning `Optional[Channel[B, A]]`. Open question.
- **One-way channels, entry takes a pair.** Entry `def f(ch: Pair[In, Out])` holding two one-way ends gets the single-parameter win without bidirectional types. Set aside: it keeps two endpoint types and still needs two handles per conversation; not measured, a taste call for Chinmay.
- **Smallest version:** tasks only, `Channel[S, R](n)`, no group integration. Proves the type and close semantics, leaves the entry rule unproven; it is stage 1 below.
- **Node model (`postMessage` + events + `workerData`).** Rejected: multiple inputs to a child.

## Simplification pass

- Removed: `Sender`, `Receiver`, `Sender.clone`, sender refcount, `fork` as a separate method, the channel id in IPC frames, the second entry parameter, the argument form, half-close, rendezvous capacity.
- Kept: one type, three methods, one entry rule.
- A user learns it from one example: construct, peer, send, receive, close.

## Drawbacks

- No fan-in: worker pools (N producers, one queue) are unsupported in v1; this is a real capability loss, not a simplification win. N producers need N pairs and a poll loop. Without `select`, reading from several channels is polling. Mitigated for the common case: fan-out/join uses `results()`, not a shared queue.
- A bidirectional end is move-only, so a task that only sends still holds a receive method it should not use; the unused direction is by convention (`Unit`).
- Close is coarse (no half-close): protocols that stream both ways and end one side early need a sentinel message.
- Unmeasured: process frame throughput and thread-queue overhead. Benefit is design-level, as the sibling proposals; no benchmark here.
- Prior art: Go channels are one-way-typed values shared by many; Rust `std::sync::mpsc` is one-way with `Sender: Clone`; Erlang mailboxes are per-process; Node `MessagePort` is bidirectional per port but with event-callback delivery and separate worker data. Manuscript differs by choosing one owner per end, typed per direction, and no callbacks.

## Staging and verification

0. Spike (no merge): can `Channel[S, R]` be a generic runtime-owned type or a Manuscript type over a byte-queue extern, and can `spawn[S, R]` infer from a function item? Go/no-go for the rest.
1. Docs: this design in canonical pages; edit the three sibling proposals. `make repo-check`.
2. `Channel` for tasks (needs TaskGroup stages 2-3 and the capture-drop fix): constructor, `peer`, `send`, `receive`, `close`, conformance fixtures (order, drain-then-none, closed send, cancel while parked, drop closes). Go/no-go: `make conform` passes on Linux, macOS, Windows.
3. `TaskGroup.spawn(entry)` returning the parent end.
4. Worker transport (after `worker-threads.md` stage for isolates): same fixture bodies as stage 2 run against `WorkerGroup`.
5. Process transport (after `child-processes.md` stage 1-2): same fixture bodies against `ProcessGroup`, including payload round-trip.
6. Diagnostics and cheat sheet.

The same fixture body running against all three groups is the parity gate. No test is disabled on any platform.

## Open questions

- Resolve before approval (decider: Chinmay):
  1. Accept bidirectional `Channel[Send, Receive]` over one-way ends plus a pair-typed entry parameter (recommend: bidirectional, per your direction), and accept losing fan-in in v1.
  2. `peer()` second call: fault (recommended) vs `Optional`.
  3. Half-close. Recommend: none in v1.
  4. Accept the stage 0 spike result as the gate for the type's implementation.
- Resolve during implementation:
  - Whether `capacity` is a required argument or defaulted.
  - Iteration (`for m in ch`) once `streams.ms` is checked.

## Rejected ideas

- `Sender.clone` multi-producer fan-in: contradicts one owner per end; needs sender refcounts and a close rule; revisit with `select`.
- Channel endpoints inside messages: needs descriptor passing and per-process routing.
- Separate `Sender`/`Receiver` views derived from `Channel`: reintroduces the two types.

## Future possibilities

- `select` over several channels, which also gives fan-in.
- Half-close (`close_send`) if protocols demand it.

## Review outcome

One independent subagent review (2026-10-24), folded in:
- Implementability was understated (generic extern type not shipped; inference of `spawn` unproven): added stage 0 spike, changed the Components rows.
- Overloaded `spawn` (channel vs plain argument) was a checker special case: argument form removed.
- `close` is `var def`: examples use `var`.
- Deadlock, unused-direction, crash and early-exit semantics, the capture-drop dependency, and the fan-in loss are now stated.
- Process `capacity` is not enforceable without credits: dropped for processes; rendezvous dropped.
- Not adopted: removing the bidirectional design. The reviewer's alternative (one-way ends in a pair parameter) is listed in Alternatives.
- Sibling proposals still say `fork` and channel ids until approval.
