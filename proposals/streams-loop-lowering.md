# Streams lower to plain loops

## Summary

- A stream item cost 100 to 400 ns where a `for` over a list costs 1.6 ns. None of it was waiting: a promise per stage per item, a `List` per `feed`, a cell round trip per item, and interface calls LLVM could not resolve.
- Stages now pull their upstream `Source` with a plain call, a `for` loop holds the source for the whole loop, and LLVM can read vtables. No user-facing API changes.
- Results: [`bench/perf/streams`](../bench/perf/streams/README.md).

## Status

Implemented 2026-11-03 on `6242dcc1`. Chinmay's direction: keep the semantics and API, find a fast lowering, and keep `map` and `lines` as pure `Transform`s.

## Decisions

- **One stream type.** Only a source that touches the system waits, inside its own `next`. A promise exists only for `read()`.
- **Direct pull.** `through` moves the input's source out of its cell (`source_of`); when a pending `read()` holds it, the stage reads through the stream as before (`Reading`), so "a read is already waiting" keeps its meaning.
- **The loop holds the source.** `Waiting` (now opaque) takes the source once and puts it back when the loop ends, breaks or fails. `msrt_cells_out` tells it whether the stream is still there; if not, the source closes with the loop. Inside the body, `s.read()` fails with `Closed` and `s.close()` takes effect at the end of the loop.
- **Readable vtables.** Each LLVM unit gets an `available_externally` copy of the vtables it names; the Cranelift object still defines them.
- **Remaining cost.** `stream-map` is about 30 ns: the one-item `List` that `Mapper.feed` returns, behind a source LLVM cannot trace. A hand `Source` chain is 2.7 ns. `Transform` now writes to a `var out: WriteStream[B]` instead of returning a `List`, which removes that allocation.

## Rejected

- `map` and `lines` as their own `Source`s (12 ns for `map`): they would stop being pure transforms.
- Generic stages over the concrete source type: the source type would show in every `ReadStream` signature.
- A separate sync stream type, or batching items in the cell.
- A MIR pass that resolves known implementations: it needs repeated inline rounds, larger budgets and forwarding through heap boxes. Readable vtables gave the same result for traceable values with one codegen change.

## Open

- A checker rule that lends `s` to `for x in s.wait()` (approved by Chinmay) would turn the in-body `read()` and `close()` cases into compile errors. It needs a new ownership form, an owned result that borrows its receiver, and is not built here.
