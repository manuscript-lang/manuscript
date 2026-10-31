# Channel[In, Out] over a pluggable Transport (design proposal)

## Summary

- Problem: `proposals/taskgroup.md` stage 4 plans one-way `Sender[T]`/`Receiver[T]`; a two-way conversation needs two pairs, and process IPC needs a different type per direction.
- Change: `Channel[In, Out]` (sends `In`, receives `Out`) is a Manuscript type with one field, `transport: Transport[In, Out]`. Each level of concurrency instantiates its own transport: task (Manuscript), worker (small Rust core), process (Manuscript framing over an OS pipe).
- Only a group creates channels: `spawn(entry)` always gives the child one end and returns the child's handle, whose `channel` field is the other end. Entries are full `def`s.
- Rust only where Manuscript cannot: park/wake for tasks, cross-isolate moves for workers, the OS pipe for processes.
- Decision requested: sign-off on the transport design.

## Status

- **Approved** by Chinmay on 2026-10-24 ("great, let's build it"). Written against `main` at `6361798f`; TaskGroup (#1166) has since landed on `main`.
- Stage 3 (processes) implemented in `stdlib/processes.ms`; see `proposals/child-processes.md` Status for the built shape.
- Stage 2 (tasks) implemented. Choices made while building it:
  - `TaskTransport` lives in `stdlib/tasks.ms`, unexported, so only `spawn` makes task channels.
  - A token lasts for one wait (`msrt_channel_token/park/post`, `crates/ms-rt/src/channel.rs`): no token outlives its wait, so a late post is dropped and nothing needs freeing at close.
  - `close()` closes the whole end; unread values on it are dropped and later calls give `Closed`. The other end drains first.
  - 16 unread values per direction before a send waits.
  - `.clone()` of a `Channel` shares the end; waiters are a list, so several senders or receivers on one end work.
  - The task's end closes in a `with` cleanup, so it closes on return, cancellation, or a cancellation before the task first ran (the "never starts" check moved into the task body, `msrt_scope_started`).
  - Time limits are now also checked on each task switch: tasks that keep each other ready never reached `reactor_wait`, where kills expired.
- Direction (Chinmay, 2026-10-24): bidirectional; `Channel` uppercase; spawn creates the ends; "spawn should return the handle ... Channel can be a field on that return type"; "i want majority of things in ms"; "tasks and workers should be just in memory, no socket, use socket pair only for processes"; "channel should have a dedicated transport field ... instantiate a different transport for different levels ... only use Rust for things that are not feasible"; "a full result, no connect. let's do full def if needed".
- Superseded drafts (git history): tuple `channel_pair`, `peer()`/`create_mirror`, `AtomicWords` ring, JSON over a pipe at every level.
- Reviews: two skeptical subagent reviews; the second (2026-10-24, against source with `ms build`) is folded in below and listed in Review outcome.

## Goals and non-goals

- Goals: one `Channel` API for `TaskGroup`, `WorkerGroup`, `ProcessGroup`; a type per direction; one entry parameter; values move in memory for tasks and workers; safe errors; as much as possible in Manuscript; Linux, macOS, Windows parity.
- Non-goals: changing group fault and result rules (their proposals); `select`, timeouts, iteration; multi-consumer queues; channel ends inside messages.

## API

```manuscript
# @std/channels.ms
interface Transport[In, Out]:
    var fn send(value: In) Result[Unit, ChannelError]
    var fn receive() Result[Optional[Out], ChannelError]   # ok(none): closed and drained
    var fn close() Unit

type Channel[In, Out]:
    transport: Transport[In, Out]

impl Channel[In, Out]:                           # thin delegation, same names
    var fn send(value: In) Result[Unit, ChannelError]: self.transport.send(value)
    var fn receive() Result[Optional[Out], ChannelError]: self.transport.receive()
    var fn close() Unit: self.transport.close()

type ChannelError:
    case Closed                                  # send after the other end closed
    case Broken(reason: String)                  # peer died, malformed or oversize frame, decode failure
```

Groups (one form for all three): the group carries the channel types, like it carries `T`, with `Unit` defaults.

```manuscript
type TaskGroup[T, In = Unit, Out = Unit]          # WorkerGroup / ProcessGroup likewise
fn spawn(entry: fn(Channel[Out, In]) T) Task[T, In, Out]   # handle.channel: Channel[In, Out]
```

- Source methods cannot declare their own type parameters (`crates/ms-check/src/passes.rs:131`; inherent methods become a synthetic contract and contracts have no per-operation generics), so `In`/`Out` live on the group. Every child of one group then has the same channel types, as it has the same `T`.
- Because the entry type is concrete, an untyped lambda infers: `group.spawn(lambda ch: fetch(url.clone()))` works for fan-out (built and run with `ms build`, 2026-10-24).

```manuscript
fn square_all(ch: Channel[Int, Int]) Result[Unit, ChannelError]:
    var c = ch                       # issue #1191: a var parameter cannot be a Callable today
    var open = true
    while open:
        if let n = try c.receive():
            try c.send(n * n)
        else:
            open = false
    return ok(unit)

fn fetch_all(urls: List[String]) Result[List[Int], TaskError]:
    with let group = TaskGroup[Int]():                 # no messages: Channel[Unit, Unit]
        for url in urls:
            group.spawn(fn ch: fetch_size(url.clone()))
        return group.results()

fn main() Int:
    with let group = WorkerGroup[Result[Unit, ChannelError], Int, Int]():   # or TaskGroup / ProcessGroup
        var worker = group.spawn(square_all)
        if worker.channel.send(3).is_error():
            return 1
        if let reply = worker.channel.receive():
            ...
        worker.channel.close()       # child's receive() returns ok(none), child returns
    return 0
```

- Worker and process entries are named top-level `def`s; tasks also take lambdas.
- `receive` returns `Result`: `ok(some(v))` a message, `ok(none)` a clean close after draining, `error(Broken(..))` a broken channel.

## Transports

| Transport | Manuscript part | Rust part | Values |
| --- | --- | --- | --- |
| `TaskTransport` | `Shared` state: two bounded queues, two closed flags, two waiter tokens; whole value appended in one step (single thread) | park/wake: existing `msrt_token_new/park/post/free` (`crates/ms-rt/src/task.rs:1003-1126`) as plain `Int` externs | moved |
| `WorkerTransport` | wrapper implementing `Transport` | small locked queue of moved values between isolates; reader records (isolate, token) under the lock with its empty check; writer posts after unlocking (`post_remote`, tokens with `TOKEN_REMOTE`); isolate exit marks its ends closed and posts peers. Needs per-isolate inboxes from the workers branch (PR #1181); today `INBOX` is one process-wide queue (`task.rs:123`) | moved |
| `ProcessTransport` | framing over `ReadStream`/`WriteStream` (`stdlib/io.ms:63-81`) with `stringify`/`parse`; receive-side leftover buffer for partial reads | OS pipe from `proposals/child-processes.md` | JSON |

- Frame (process): 4-byte LE length, 1 kind byte (`message`, `close`, `result`), UTF-8 JSON body. Default cap 16 MiB; larger, unknown kind, or invalid UTF-8 is `Broken` and poisons the channel. `Unit` and other no-form values use an empty body (`stringify(())` is `InvalidData` today, tested).
- Frame order: messages, then `close`, then `result`, then EOF. `result` is never returned by `receive`; `result()` reads it, dropping unread messages (bounded by the cap).
- Mid-frame cancellation: the frame write is shielded; a cancelled `receive` keeps its partial bytes in the leftover buffer.
- No drop hook exists for source types (`documentation/core-language/cleanup/resource-release.md:13`), so close is explicit: the group closes the child's end when the entry returns, and closes every handle's end on group close. A leaked end is covered by the group's close; worker ends are also closed by isolate exit.

## Payload rules

- Task: any type (same thread).
- Worker: the worker-boundary check from `proposals/worker-threads.md` (no `Resource`, `Shared`, closures, `ref`).
- Process: a new checker rule on `ProcessGroup.spawn`: `In`, `Out` and `T` must be plain data (scalars, `String`, `Bytes`, lists, sets, maps with scalar or `String` keys, records, alternatives, `Optional`, `Result`) with no custom `JsonEncode`. Needed because `stringify` accepts every type today: a record with a `Callable` field encodes as `{}`, `some(none)` comes back as `none`, `NaN` becomes `null` (all tested). Non-finite `Float` at send is `Broken`.

## Semantics

- Close: `close()` by either end; the other end drains, then `receive()` returns `ok(none)` and `send` returns `error(Closed)`.
- Process close order: `Process.close()` closes the channel, which the child sees as cancel (`proposals/child-processes.md:85`); call `result()` before `close()` to wait for a result.
- Faults: unchanged per group (tasks and workers abort the process; processes per their proposal). The shared fixture body covers messages and close, not faults.
- Deadlocks: two peers that both send into full queues park forever; with `TOKEN_REMOTE` the scheduler cannot report it (`task.rs:610`). Documented, not detected.
- Windows: no polling. The channel pipe is an owner-only named pipe opened for overlapped I/O and registered with the runtime poller through `mio::windows::NamedPipe` (`mio` already builds with `os-ext`, `crates/ms-rt/Cargo.toml:19`), so reads and writes park and wake like sockets on Unix, with backpressure. On Unix the socketpair is waited on with epoll/kqueue through the same poller; both park the task with real backpressure. The 1 ms polling in `crates/ms-std-process/src/plat/windows.rs:29-55` (today's anonymous stdio pipes) is not used for channels; the child-processes thread moves those stdio pipes onto the same named-pipe readiness path first (Chinmay, 2026-10-24: "i don't want random polling").

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/channels.ms` (new) | `Transport`, `Channel`, `ChannelError`, `TaskTransport`, `ProcessTransport` | order, drain-then-none, closed send, broken channel, malformed/oversize frame, `Unit` round trip |
| `crates/ms-rt` | token externs; worker queue (with PR #1181) | cross-isolate wake, exit closes ends |
| `crates/ms-check` | process payload rule; issue #1191 (var-parameter `Callable`) | accept/reject fixtures |
| group stdlib modules | `spawn(entry)` takes a channel entry and returns a handle with a `channel` field; replaces `spawn(Callable[[], T])` from the TaskGroup plan | one fixture body per group, built with `ms build` |
| syntax, formatter, LSP, CLI | unchanged | none |
| docs, `ms guide` | channel section | docs build |

## Verification

- `ms build` passes a stub of `Transport`, `Channel` and a `Shared`-backed `TaskTransport` (not in the repo).
- Review findings above were reproduced with `ms build`/`ms run` scratch programs; `var` parameter entries fail lowering (issue #1191).
- Unverified: worker and process transports, frame code.

## Alternatives

- **Do nothing (one-way `Sender`/`Receiver`).** Two types per conversation.
- **JSON over a pipe at every level.** One code path, but copies and JSON limits for tasks and workers; rejected by the owner.
- **Atomics and word intrinsics.** Too complex for the gain.
- **A separate `connect(entry)` beside `spawn(work)`.** Keeps `spawn(lambda: work(x))`; rejected by the owner in favor of one form with full `def` entries.
- **`receive() -> Optional[Out]` plus `error()`.** Simpler loops; rejected by the owner for a full `Result`.

## Drawbacks

- Three transports to test instead of one.
- A new checker rule for process payloads.
- Fan-out without messages now needs a `def` taking `Channel[Unit, Unit]`; `spawn(lambda: f(x))` no longer works. Changes `proposals/taskgroup.md` (handle-free v1, `spawn(Callable[[], T])`).

## Staging

0. Issue #1191 (var-parameter `Callable`); entries rebind with `var` until it is fixed.
1. Docs.
2. `TaskTransport` + `TaskGroup.spawn(entry)` (after TaskGroup stages 2-3).
3. `ProcessTransport` with the child-processes stages.
4. `WorkerTransport` with the worker-threads stages.

Gate: `make conform`, `make verify` on Linux, macOS and Windows with `ms build`, not only `ms check`; no test disabled on any platform.

## Open questions (decider: Chinmay)

1. None open. `spawn` typing resolved by group-level `In`/`Out` with `Unit` defaults (no checker change).

## Decided (Chinmay, 2026-10-24)

- One `spawn(entry)` form with full `def` entries; no `connect`.
- `receive() -> Result[Optional[Out], ChannelError]`.

## Review outcome (2026-10-24, second review)

- Folded in: var-parameter entries fail lowering (issue #1191); `Unit` not encodable; `stringify` accepts every type, so a process payload rule is needed; an error surface; no drop hook in source types; mid-frame cancellation; frame order and result reading; Windows pipe polling; cross-isolate wake rules; spawn inference for lambdas; frame size cap.
- What held: `stringify`/`parse[Out]` work in generic code; records with defaults round-trip; `var c = worker.channel` borrows rather than moves.
