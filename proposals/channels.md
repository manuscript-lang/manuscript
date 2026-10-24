# Channel[In, Out]: a bidirectional endpoint and `create_mirror` (design proposal)

## Summary

- Problem: `proposals/taskgroup.md` stage 4 plans one-way `Sender[T]`/`Receiver[T]`; two-way conversation needs two pairs and four endpoints, and process IPC needs a different type per direction.
- Change: one type `Channel[In, Out]` that sends `In` and receives `Out`, created with `Channel[A, B](capacity)`; `create_mirror(ch: Channel[A, B]) -> Channel[B, A]` returns the connected opposite end.
- Scope (Chinmay, 2026-10-24): the type and the helper only. Worker, process and task-group entry shapes and transports stay in their own proposals; they take a `Channel`.
- No language change: the earlier tuple-returning `channel_pair` was dropped because the language has no tuples (`documentation/core-language/basics/expressions.md:158`); `create_mirror` returns one value.
- Decision requested: sign-off on the `Channel` shape and on the second-mirror rule (open question 1).

## Status

- Proposal, 2026-10-24, against `main` at `6361798f`. Nothing implemented.
- Direction (Chinmay, 2026-10-24): "channels should be bidirectional"; keep `Channel` uppercase; "scope the work in this thread to allow Channel[In, Out] and a helper function"; then, since the language has no tuples: "the channel_pair function needs to be changed to something create_mirror(in: Channel[A, B]) -> Channel [B, A]".
- Review: an earlier broader draft had one skeptical subagent review; findings that still apply are folded in. The narrowed proposal needs a fresh review before approval.

## Problem

- One-way endpoints double the handles and the entry parameters for every request/response protocol.
- A single `Channel[T]` is not enough: a process child may receive `Bytes` and reply `String`.
- Two connected ends need either a constructor that returns two values (the language cannot express that) or a way to derive the second end from the first.

## Goals and non-goals

- Goals:
  - `Channel[In, Out]` with `send`, `receive`, `close`;
  - `create_mirror` returning the connected opposite end, typed so that what one sends the other receives;
  - Linux, macOS and Windows at parity.
- Non-goals:
  - group entry rules, `spawn`, worker or process transport (their proposals);
  - `select`, timeouts, iteration, fan-in and endpoint cloning, half-close, rendezvous capacity;
  - sending channel endpoints inside messages.

## Design

### API (`@std/channels.ms`)

```manuscript
from "@std/channels.ms" import Channel

# Channel[In, Out]: sends In, receives Out
var def send(value: In) -> Result[Unit, Closed]   # consumes value; parks while full; cancellation point
var def receive() -> Optional[Out]                # owned value; none once the peer is closed and drained
var def close() -> Unit                           # Closeable; idempotent; drop does the same

Channel[A, B](capacity: Int) -> Channel[A, B]     # constructor: a new connected channel, one end
def create_mirror[A, B](ch: Channel[A, B]) -> Channel[B, A]   # the connected opposite end
```

```manuscript
from "@std/channels.ms" import Channel, create_mirror

var mine = Channel[Int, String](4)      # sends Int, receives String
var theirs = create_mirror(mine)        # Channel[String, Int]: sends String, receives Int
```

- Ends are symmetric: what one sends the other receives. One-way use ignores a direction (`Channel[Job, Unit]`); same-type duplex is `Channel[T, T]`.
- `create_mirror` is a plain generic function (the language has no static methods); `Channel` stays uppercase and is constructed like any generic type.
- Entry parameters and bindings that send, receive or close must be `var` (`ms check` rejects them otherwise; `Closeable.close` is `var def`, `stdlib/core.ms:64`).

### Semantics

- Ownership: `send` moves its argument; `receive` returns an owned value; each end is move-only.
- Mirror rule: a channel has exactly one mirror. `create_mirror` borrows `ch`, so the borrow rules cannot stop a second call; instead the second call (and any call on a mirror made earlier) returns an end that is **born closed**: `send` returns `Closed`, `receive` returns `none`. A safe error, no fault, no `Optional`. Cost: a hidden "mirrored" mark on the channel; alternatives in Alternatives.
- Close: `close()` or dropping an end closes the conversation from that side. The peer's `receive()` drains buffered values, then returns `none`; the peer's `send` returns `Closed` and drops the value. Safe errors, not faults.
- Capacity: `capacity >= 1` bounds each direction. No rendezvous in v1.
- Cancellation: `send` and `receive` are cancellation points.
- Limits stated, not solved: a task holding both ends, or two peers that both `send` first on a full channel, park forever (`crates/ms-rt/src/task.rs:611` faults only when every task is parked); a holder can call `receive` on an unused direction and park; no half-close and no fan-in, so worker pools are unsupported in v1.
- Leak: captures of a cancelled or faulted task are not dropped (`proposals/taskgroup.md:49`), so a cancelled task's end is not dropped and the peer can park forever. Implementation is conditional on the capture-drop fix.

### Transport

- Unchanged by this proposal: the `Channel` API is the same whatever the peer's location (queue, moved value across threads, JSON frames across processes). `Channel(...)` and `create_mirror` create same-thread ends; other-location ends are created by their group's `spawn`, specified in those proposals.

## Components touched

| Component | Change | Risk / test |
| --- | --- | --- |
| `stdlib/channels.ms` (new) | `Channel[In, Out]` with its constructor, `Closed`, `create_mirror`. Externs are not generic and `extern type` is "planned, not shipped" (`skills/runtime/SKILL.md:18`): either a generic runtime-owned type with per-`T` drop and move through `TypeDesc`, or `Channel` in Manuscript over a non-generic byte-queue extern (stage 0 spike) | conformance: order, close, drain, closed send |
| `crates/ms-rt` | endpoint pair, waiter tokens, close flags | runtime tests; cancel while parked |
| `crates/ms-syntax`, `ms-check`, `ms-lower`, formatter, LSP | unchanged (ordinary generic type and function) | symbol search shows `Channel` |
| `documentation/core-language/`, `ms guide` | channel section | docs build |
| `proposals/taskgroup.md`, `worker-threads.md`, `child-processes.md` | replace `Sender`/`Receiver`/`fork` channel plans with `Channel`; edited after approval | consistency check |
| CLI, build, cache | unchanged | none |

## Examples

Illustrative, same-thread pair (the group API is a sibling proposal):

```manuscript
def serve(var ch: Channel[Int, Int]) -> Unit:
    var open = True
    while open:
        if let n = ch.receive():
            ch.send(n * n)
        else:
            open = False
```

Caller:

```manuscript
def run() -> Unit:
    var mine = Channel[Int, Int](4)
    var theirs = create_mirror(mine)
    # hand `theirs` to a task: lambda: serve(var theirs)
    mine.send(3)
```

## Verification of examples

- `ms check` built from `6361798f` against a stub declaring `Channel`, `Closed`, a function standing in for the `Channel(n)` constructor, and `create_mirror`, all with fake bodies (not in the repo). Passing: `serve`, and `run` above with `theirs` captured by `lambda: serve(var theirs)`.
- Found by the check: entry parameters and mutated bindings need `var`; `if let` binds immutably, so an `Optional` mirror would need `var owned = theirs` (another reason `create_mirror` returns a plain `Channel`); the language has no `record`, `guard` or tuples.
- Proposed, unverified: the runtime types, the constructor taking a capacity on a runtime-backed generic type, and the born-closed behavior.

## Alternatives

- **Do nothing / one-way `Sender`+`Receiver`.** Cheapest; already planned. Costs two types and more handles per conversation.
- **`channel_pair` returning a tuple.** Needs tuples, which the language lacks.
- **Two-field `ChannelPair` record.** No hidden state, no second-call case; but `first`/`second` naming was judged unclear.
- **`create_mirror` returning `Optional` or `Result` on a second call.** Explicit, but the caller must unwrap, and `if let` binds immutably so a `var` copy is needed.
- **`create_mirror` that faults on a second call.** Rejected: misuse should be a safe error (Chinmay, TaskGroup thread).
- **Static method `Channel.pair`.** The language has no static methods (`types/contracts.md:76`).
- **Smallest version:** `Channel` for tasks with `create_mirror`; proves the type and close semantics.

## Drawbacks

- `create_mirror` keeps a hidden "mirrored" mark; ownership does not enforce the single mirror, so the second call yields a dead end rather than a compile error.
- Bidirectional ends carry an unused direction by convention; no half-close; no fan-in.
- Prior art: Go channels are one-way-typed shared values; Rust `mpsc` is one-way with a cloneable `Sender`; Node `MessageChannel` ports are bidirectional but event-driven. Manuscript differs: typed per direction, one owner per end, no callbacks. Benefit is design-level; nothing measured.

## Staging and verification

0. Spike (no merge): generic runtime-owned type vs Manuscript-over-byte-queue; a generic constructor with a capacity argument.
1. Docs: this design in canonical pages.
2. `Channel` and `create_mirror` for same-thread tasks (needs TaskGroup stages 2-3 and the capture-drop fix); conformance fixtures: order, drain-then-none, closed send, cancel while parked, drop closes.
3. Group integration in the sibling proposals.

Go/no-go per stage: `make conform`, `make verify`; Linux, macOS and Windows; no test disabled on any platform.

## Open questions

- Resolve before approval (decider: Chinmay):
  1. Second `create_mirror` on the same channel: born-closed end (recommended), `Optional`, or fault.
  2. Accept the stage 0 spike result as the implementation gate.
- Resolve during implementation: `capacity` required or defaulted.

## Rejected ideas

- Endpoint cloning and fan-in: conflicts with one owner per end; revisit with `select`.
- Channel endpoints inside messages: needs descriptor passing.

## Future possibilities

- `select` over several channels, which also gives fan-in.
- Half-close if protocols demand it.
