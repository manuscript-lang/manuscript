# Stackless generators: `yield` replaces `Source`

## Summary

- Problem: a stream step that keeps state between items is a hand-written state machine behind `impl Source[T]`. `Lines` is 70 lines (`stdlib/io/streams.ms:9-78`); `Mapped`, `Filtered` and `Taker` each need a type, an `impl` and a `close`.
- Change: a function that contains `yield` and returns `ReadStream[T]` compiles to a stackless state machine that the compiler wraps as a `Source`. Source-written adapters move over first; whether `Source` itself can go is decided after that (22 `impl Source` sites in `stdlib/`, most over native handles).
- Decision requested: approve the language change (`yield` becomes a keyword) and stages 1 and 2. Stage 3 is a goal, not a commitment.

## Status

- Proposal, 2026-11-06, against `main` at the thread branch base. Direction (Chinmay): "lets do a stackless, if this works, i would like to get rid of Source altogether and only use generator functions for source".
- The parser rejects `yield` today on purpose (`ms-syntax/src/parser.rs:1872`); `crates/DESIGN.md` decision 4 says there is no language-level concurrency. A generator adds none: it runs on its consumer's stack.

## Problem

- `Lines` needs `data`, `start`, `ended` and a resumable loop because `next` cannot suspend mid-loop. As a generator it is one `for` loop with a `yield`.
- Stackful coroutines (`ms-rt/src/task.rs`) would give `yield` without a compiler change but cost two context switches and a stack per item stream (unmeasured), which the per-item adapters cannot afford. Stackless has neither cost.

## Design

Proposed syntax (does not check on `main`; the parser rejects `yield`):

```
export fn lines(input: ReadStream[Bytes], max_bytes: Int? = none) ReadStream[String]:
    var held = "".to_bytes()
    for chunk in input:
        held = held.concat(chunk)
        while let end = held.index_of_byte(10, 0):
            yield try decode(held.slice(0, end))
            held = try held.slice(end + 1, held.length())
    if held.length() > 0:
        yield try decode(held)
```

- Rule: a function whose body contains `yield value` declares `ReadStream[T]` as its result and `value` is a `T`. A call runs nothing; it returns a stream that runs the body to the next `yield` on each `next()`.
- Ending: falling off the end or a bare `return` ends the stream (`next()` is `ok(none)`). `try e` and `return error(e)` end it with that error. After either, `next()` keeps answering `ok(none)`.
- Close and drop: `close()` stops the body where it is and drops what it holds (locals, parameters) in reverse declaration order, then closes owned streams as drop does today (`ReadStream.close`, `stdlib/io/io.ms`). A generator never runs user code after the consumer stops.
- Ownership: parameters move into the state; a borrowed parameter is rejected (the generator outlives the call). A yielded value moves to the consumer. Locals live in the state across yields, so one owner per value holds with no new rule.
- Restriction (v1): `yield` is a statement whose operand holds no resource temporary, and is rejected inside a `with`/cleanup scope and inside a closure. A pending cleanup (`CleanupPush`, `ms-lower/src/close.rs:378,733,1253`, also pushed for resource temporaries) would sit on the runtime cleanup stack while the consumer runs and break its LIFO order. The checker rejects a `yield` with any live cleanup handle; hold a resource as a local instead, dropped on close.
- Cancellation and faults: a fault in `next` aborts as today (no unwind). A cancelled `next` leaves the state at the last `yield`; `close()` still runs and drops the live set.
- Lowering (`ms-lower`): the body is lowered to one `next` function over a heap state record (a new MIR record type, not `slotify`: `func.rs:1157` emits a frame `Op::Slot` that does not survive a return). Every local of a generator, including the hidden counters and iterators of `for` and `while`, lives in the record and is reached through `Local.slot`, the pointer path closures already use for shared mutable variables. No SSA value lives across a `yield`, so the builder's lazy SSA needs no change at the resume edge, and no liveness pass is needed. Spilling live SSA values instead was rejected: the scope-end drops would consume them a second time.
- `next` begins with a switch on the record's `state` word that jumps to the block after the last `yield`; a `yield` stores the value, sets `state` and returns. Generics (`map[T, U]`) get one record per instance; a callback parameter is a record field called like any field closure.
- Drop glue: per state, `close()` drops exactly the fields live at that `yield`, using `move.out` and `rec.fill`; a flag per field is used only where the live set is not fixed by the state. Stage 1 starts with a hand-written MIR fixture for `lines` that the verifier accepts, because linear ownership across the mid-function entry is the main risk.
- Interface: the compiler wraps the state as a `Source[T]` (vtable `next`, `close`), so `ReadStream.next` costs what it does today (`closed` and `EndedSource` unchanged).
- Checker (`ms-check`): `yield` typing, the return-type rule, the borrowed-parameter and scope restrictions, and a diagnostic for `yield` outside a function. The formatter and LSP learn the keyword.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | `yield` statement, formatter | parse and format fixtures, rejected-position cases |
| `ms-check` | typing, restrictions, diagnostics | conformance accept and reject cases |
| `ms-lower` | state record, resume switch, drop flags | MIR fixtures, `make conform`, `make e2e` |
| `ms-mir` | state record type; verifier must accept the mid-function entry (unproven) | MIR fixture, `cargo nextest run -p ms-mir` |
| `stdlib/io/streams.ms` | `lines`, `map`, `filter`, `take` as generators | existing stream tests |
| `stdlib/io/io.ms`, natives (`natiface.rs`) | stage 3 only if feasible: fewer `Source` impls | e2e stream fixtures on all platforms |
| docs, wiki, `VISION.md`, `DESIGN.md` | generators section, decision 4 note | `make docs-check` |

## Alternatives

- Do nothing: four small types stay; every new stateful step costs a state machine. Rejected by direction.
- Stackful generators on `task.rs`: smallest compiler change, but a stack per generator and two switches per item on the hot adapters. Rejected; measure only if stackless fails.
- A new `Generator[T]` type: one more name for something `ReadStream[T]` already is. Rejected.
- Keep `Source` as the internal interface (what stage 1 does): `ReadStream` dispatch is unchanged. Deleting it means a sum type of handle and generator, which still needs a vtable, so it is not obviously simpler.
- A `Stepper` helper (a `Source` built from a closure): no language change, but the closure cannot suspend mid-loop, so `Lines` stays a state machine.

## Stages

1. Syntax, checker and lowering for a single `yield` in straight-line code and loops; accept/reject fixtures; gate: MIR verifier and `make conform` pass on all platforms.
2. Port `Mapped`, `Filtered`, `Taker`, `Lines`; gate: perf kernel for `map`/`filter`/`take` no slower than `Source` on the latest `bench/perf` baseline, results added as a dated section.
3. Convert further `impl Source` sites that are pure Manuscript (of 22, `DescriptorSource`, `PipeSource`, net and process sources wrap native handles); delete `Source` only if none remain. Gate: `make verify-full`, full CI matrix dispatched.

## Open questions

- Can native handles become generators over a native read call? A blocking read parks the consumer's task, which is fine, but 22 sites need a look. Recommend deciding after stage 2.
- Should `yield` be allowed under `with` once the cleanup stack can suspend a scope? Recommend not in v1.
