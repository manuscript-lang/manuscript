# Iteration end: tell "no more items" from a null item

## Summary

- Problem: `next() T?` ends at `null`, so once `T?` collapses (`T??` is `T?`) a stream, pipe or iterator of a nullable `T` ends at its first null item, and a generic reader of `T?` cannot tell "nothing queued" from "a null arrived".
- Change: one end-of-iteration protocol for `Iterator`, `ReadStream`, pipes and the `for` loop in which the end is its own value, never a `T`. Promise results taken from a slot keep the internal `Slot[T]`.
- Decision requested: pick option B (a `Next[T]` enum, recommended), C (non-nullable items only), or A (document the loss).

## Status

Proposal, 2026-11-23. Follows [nullable-types](nullable-types.md) stage 1. Chinmay: "no i think we should have a better and consistent api" (not an internal workaround).

## Problem

```ms
fn var Blanks.next() Int?:
    // yields 1, null, 3, then ends
```

`for x in Blanks()` must walk three items. With `T?` as the protocol type the second `null` ends the loop. Evidence:

- 24 `fn var ....next()` implementations in `stdlib/` return `T?` or `T?!` (`io.ms`, `streams.ms`, `steps.ms`, `net/`, `os/`, `time.ms`, `cli/terminal.ms`, and others) plus three interface declarations, and 70 stdlib and fixture files call `.next()`.
- `Iterator[T].next`, `ReadStream[T].next` and `pipe_next[T]` share the problem; `lower_for.c` reads the answer with `OptGet` and the payload type of the optional.
- Only one fixture ever yielded a null item (`stream-resource-lifetime`'s nested-optional test, removed by nullable stage 1); no non-generic stdlib source does. Six sources are `T?` pass-throughs of unknown nullability (`Taker`, `Through`, `Mapped`, `Filtered`, `ListSource`, `PipeSource`).
- The pipe runtime has the same hole: `pipe_next` (`io.ms:342`) reads `msrt_pipe_try[T]` and `msrt_promise_take[T]` as `T?`.

## Design

Rule: `next` answers a value that says whether an item follows, not an optional `T`.

```ms
export enum Next[T]:
    item(value: T)
    done

fn var Blanks.next() Next[Int?]:
    ...
```

- `for x in source` calls `next` until `done`; `x` is the item, nullable or not. Users who write `for` never see `Next`.
- `Iterator[T].next() Next[T]`; `ReadStream[T].next() Next[T]!`; `pipe_next[T]() Next[T]!`.
- `Next` is an ordinary prelude enum with the layout rules of other enums: a tag plus the payload, no allocation.
- `return item(x)` and `return done` replace `return x` and `return null`; the `T?` to `T` conversion that wraps a plain `T` does not apply, so the new spelling is explicit.
- Promise results keep `Slot[T]` inside `taken_result`; `Next` is not reused there, because a taken result is "value or gone", not "item or end".

### Options

- A. Status quo: document that streams of a nullable `T` end at the first null. No code change; the hole stays, and a generic reader of `T?` is wrong for nullable `T` without any diagnostic.
- B. `Next[T]` enum (above). Cost: rewrite 25 stdlib sources, user iterators, `lower_for.c`, the `Iterator` and `ReadStream` interfaces, and docs; benefit: no ambiguity anywhere, same protocol for streams, pipes and iterators.
- C. Keep `T?` and bound the element: `Iterator[T]` and `ReadStream[T]` reject a nullable `T` (`ReadStream[Int?]` is a diagnostic, wrap it in a record). Cost: one checker rule and no migration; benefit: no ambiguity for the types that exist; drawback: a stream of optional values needs a wrapper type by hand.

Recommendation: B, in one step with no bridge. A bridge that reads `next() T?` as `Next[T]` cannot know whether a generic `T` is nullable, so it would hide the ambiguity; instead a `next` that returns `T?` is a diagnostic that says to return `Next[T]`, with a machine fix for non-generic declarations. C is the fallback if B's migration is judged too large.

### Adapters

`Mapped`, `Filtered`, `Through` and `Taker` read `item := self.input.next()?` then `if value := item`; they become `match item:` with `item(value)` and `done` arms, or an early `done` return, kept flat (no nested `match`). `Through` also pops its buffer (`steps.ms:103`) and returns `item(x)` or `done`. `Taker` passes the input's `Next` through unchanged, which is where a null item used to break.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core/core.ms`, `io/*.ms`, `net/`, `os/`, `time.ms`, `cli/` | `Next[T]` in prelude; 24 `next` implementations; `read_bounded` and `ReadStream.next(timeout)` return `Next[T]!` | each module's conformance fixture |
| `stdlib/io/io.ms` pipes | `pipe_next` takes `Slot[T]` from `msrt_pipe_try` and `msrt_promise_take`, so a null item is not "empty"; `Pipe.receive` and `net/router.ms` follow | pipe fixture of `Int?` |
| `src/compiler/check/bodies.c` | `element_type` unwraps `Next[T]` and `Next[T]!` beside `Optional` and `Result`; the `next() T?` diagnostic | check fixtures |
| `src/compiler/lower/lower_for.c` | tag test and payload read in the interface-dispatch and direct paths; the three item-ownership branches (`MK_ALT`, `fn_take_payload` with `fn_bind_closing`, `OptGet`) become one rule: the item moves out of `Next.item` and closes at the end of its round | closing-resource and stream fixtures |
| `documentation/core-language/control-flow`, streams guide | the protocol and migration | `make docs` |

New fixtures: `for` over a source yielding 1, null, 3; a closing resource item; `Next[T]!` with `?`; a pipe of `Int?`.

## Alternatives

- Two calls (`has_next` and `next`): Java style. A stream read can fail or wait between the calls, so the pair cannot be atomic; rejected.
- A sentinel item per type: needs a value no item can take; rejected.
- Do nothing (A): cheapest, and it leaves the nullable-element hole this proposal exists to close.

## Open questions

- Name: `Next` with cases `item` and `done` (recommended), or `Step`, `Yield`.
