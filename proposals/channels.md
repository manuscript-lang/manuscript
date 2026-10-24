# Channel[In, Out]: a bidirectional endpoint and `channel_pair` (design proposal)

## Summary

- Problem: `proposals/taskgroup.md` stage 4 plans one-way `Sender[T]`/`Receiver[T]`; two-way conversation needs two pairs and four endpoints, and process IPC needs a different type per direction.
- Change: one type `Channel[In, Out]` that sends `In` and receives `Out`, plus a helper `channel_pair[A, B](capacity) -> (Channel[A, B], Channel[B, A])` that returns the two connected ends.
- Scope (Chinmay, 2026-10-24): this proposal covers the type and the helper only. Worker, process and task-group entry shapes and transports stay in their own proposals; they will take a `Channel` and need nothing else from this one.
- Blocker: the helper returns a tuple and **the language has no tuples today** (`documentation/core-language/basics/expressions.md:158`; `types/destructuring.md`: "Parenthesized patterns such as `let (a, b) = value` are not binding patterns"). A tuple type, expression and pattern is a language change that needs your explicit go-ahead.
- Decision requested: approve adding 2-tuples (or pick the fallback below), and sign off on the `Channel` shape.

## Status

- Proposal, 2026-10-24, against `main` at `6361798f`. Nothing implemented.
- Direction (Chinmay, 2026-10-24): "channels should be bidirectional"; keep `Channel` uppercase; "scope the work in this thread to allow Channel[In, Out] and a helper function for channel_pair, return a tuple ... (Channel[A, B], Channel[B, A])"; "near/far is really unclear, the original idea of channel_pair() function returning two channels is good".
- Review: an earlier broader draft had one skeptical subagent review; findings that still apply are folded in. The narrowed proposal needs a fresh review before approval.

## Problem

- One-way endpoints double the handles and the entry parameters for every request/response protocol.
- A single `Channel[T]` is not enough: a process child may receive `Bytes` and reply `String`.
- A pair of connected ends needs a constructor that returns two values; the language cannot express that.

## Goals and non-goals

- Goals:
  - `Channel[In, Out]` with `send`, `receive`, `close`;
  - `channel_pair[A, B](capacity)` returning both ends, typed so that what one sends the other receives;
  - Linux, macOS and Windows at parity.
- Non-goals:
  - group entry rules, `spawn`, worker or process transport (their proposals);
  - `select`, timeouts, iteration, fan-in and endpoint cloning, half-close, rendezvous capacity;
  - sending channel endpoints inside messages.

## Design

### API (`@std/channels.ms`)

```manuscript
from "@std/channels.ms" import Channel, channel_pair

# Channel[In, Out]: sends In, receives Out
var def send(value: In) -> Result[Unit, Closed]   # consumes value; parks while full; cancellation point
var def receive() -> Optional[Out]                # owned value; none once the peer is closed and drained
var def close() -> Unit                           # Closeable; idempotent; drop does the same

def channel_pair[A, B](capacity: Int) -> (Channel[A, B], Channel[B, A])
```

```manuscript
var (mine, theirs) = channel_pair[Int, String](4)
# mine: Channel[Int, String]   theirs: Channel[String, Int]
```

- Ends are symmetric: the first sends `A` and receives `B`, the second the reverse. One-way use ignores a direction (`Channel[Job, Unit]`); same-type duplex is `Channel[T, T]`.
- `channel_pair` is a plain generic function, not a static method (the language has none) and not a lowercase constructor of `Channel`; `Channel` stays uppercase.
- Entry parameters and bindings that send, receive or close must be `var` (`ms check` rejects them otherwise; `Closeable.close` is `var def`, `stdlib/core.ms:64`).

### Tuples (language change, needs approval)

- Needed: a 2-tuple type `(A, B)`, expression `(a, b)`, and binding pattern `var (a, b) = ...` that moves each element out (ownership: each element is moved once, as record destructuring does; checked on a stub, see Verification).
- Smallest version: 2-tuples only, as a return type and destructuring source; no tuple indexing, no 3+ arity, no tuple in fields or parameters. That is enough for the helper and avoids a general tuple feature.
- Fallback with no language change: `channel_pair` returns a two-field type `ChannelPair[A, B]` (`first`, `second`) destructured with `var {first: mine, second: theirs} = ...`. Verified to check today on a stub. Cost: one extra named type and a pattern that renames fields.
- Not decided here: whether tuples are a general feature (VISION, grammar, formatter, LSP, docs). The proposal only requests the minimum for `channel_pair`.

### Semantics

- Ownership: `send` moves its argument; `receive` returns an owned value; each end is move-only.
- Close: `close()` or dropping an end closes the conversation from that side. The peer's `receive()` drains buffered values, then returns `none`; the peer's `send` returns `Closed` and drops the value. Safe errors, not faults.
- Capacity: `capacity >= 1` bounds each direction. No rendezvous in v1.
- Cancellation: `send` and `receive` are cancellation points.
- Limits stated, not solved: a task holding both ends, or two peers that both `send` first on a full channel, park forever (`crates/ms-rt/src/task.rs:611` faults only when every task is parked); a holder can call `receive` on an unused direction and park; no half-close and no fan-in, so worker pools are unsupported in v1.
- Leak: captures of a cancelled or faulted task are not dropped (`proposals/taskgroup.md:49`), so a cancelled task's end is not dropped and the peer can park forever. Implementation is conditional on the capture-drop fix.

### Transport

- Unchanged by this proposal: the `Channel` API is the same whatever the peer's location (queue, moved value across threads, JSON frames across processes). `channel_pair` creates same-thread ends; other-location ends are created by their group's `spawn`, specified in those proposals.

## Components touched

| Component | Change | Risk / test |
| --- | --- | --- |
| `stdlib/channels.ms` (new) | `Channel[In, Out]`, `Closed`, `channel_pair`. Externs are not generic and `extern type` is "planned, not shipped" (`skills/runtime/SKILL.md:18`): either a generic runtime-owned type with per-`T` drop and move through `TypeDesc`, or `Channel` in Manuscript over a non-generic byte-queue extern (stage 0 spike) | conformance: order, close, drain, closed send |
| `crates/ms-rt` | endpoint pair, waiter tokens, close flags | runtime tests; cancel while parked |
| `crates/ms-syntax`, `ms-check`, `ms-lower` | 2-tuple type, expression, pattern (or none, with the fallback) | accept/reject fixtures; ownership of moved elements |
| formatter, lint, LSP, VS Code | tuple syntax (or unchanged with the fallback) | formatter round trip |
| `documentation/core-language/`, `ms guide` | channel section; tuples if approved | docs build |
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

Rejected today, accepted if tuples are approved: `var (mine, theirs) = channel_pair[Int, Int](4)`. Current diagnostic: parenthesized patterns are not binding patterns.

## Verification of examples

- `ms check` built from `6361798f` against a stub declaring `Channel`, `Closed` and `channel_pair` with fake bodies (not in the repo). Passing: the `serve` function, and the fallback `var {first: mine, second: theirs} = channel_pair[Int, Int](4)` with `mine`/`theirs` moved into a `lambda: serve(var theirs)`.
- Not verifiable until tuples exist: `var (mine, theirs) = ...` and the tuple return type.
- Found by the check: entry parameters need `var`; the language has no `record`, `guard` or tuples; source methods cannot declare their own type parameters.
- Proposed, unverified: the runtime types and the `Channel` declaration.

## Alternatives

- **Do nothing / one-way `Sender`+`Receiver`.** Cheapest; already planned. Costs two types and more handles per conversation.
- **Two-field `ChannelPair` (the fallback above).** No language change; names `first`/`second` are neutral but need renaming at the call site.
- **`Channel[A, B](n)` returning one end plus `peer()`.** Needs a hidden "already taken" flag and an `Optional`; rejected, ownership does the same job without state.
- **Static method `Channel.pair`.** The language has no static methods (`types/contracts.md:76`).
- **Smallest version:** `Channel` plus the fallback record, no tuples; proves the type and close semantics.

## Drawbacks

- Tuples are a language-level addition for one function; once present, users will use them elsewhere, and docs, formatter and LSP must follow.
- Bidirectional ends carry an unused direction by convention; no half-close; no fan-in.
- Prior art: Go channels are one-way-typed shared values; Rust `mpsc` is one-way with a cloneable `Sender`; Node `MessageChannel` ports are bidirectional but event-driven. Manuscript differs: typed per direction, one owner per end, no callbacks. Benefit is design-level; nothing measured.

## Staging and verification

0. Spike (no merge): generic runtime-owned type vs Manuscript-over-byte-queue; confirm tuple moves.
1. Docs: this design in canonical pages.
2. Tuples (if approved): syntax, checker, lowering, formatter, LSP, fixtures.
3. `Channel` and `channel_pair` for same-thread tasks (needs TaskGroup stages 2-3 and the capture-drop fix); conformance fixtures: order, drain-then-none, closed send, cancel while parked, drop closes.
4. Group integration in the sibling proposals.

Go/no-go per stage: `make conform`, `make verify`; Linux, macOS and Windows; no test disabled on any platform.

## Open questions

- Resolve before approval (decider: Chinmay):
  1. Add 2-tuples (minimum scope above), or use the `ChannelPair` fallback? Recommend: tuples if you want them as a general feature; otherwise the fallback.
  2. Accept the stage 0 spike result as the implementation gate.
- Resolve during implementation: `capacity` required or defaulted.

## Rejected ideas

- Endpoint cloning and fan-in: conflicts with one owner per end; revisit with `select`.
- Channel endpoints inside messages: needs descriptor passing.

## Future possibilities

- `select` over several channels, which also gives fan-in.
- Half-close if protocols demand it.
