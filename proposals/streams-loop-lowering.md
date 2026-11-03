# Streams lower to plain loops

## Summary

- A stream item costs 100 to 150 ns where a `for` over a list costs 1.6 ns. None of it is waiting: it is a promise per stage, a `List` per `feed`, and a runtime cell round trip per item.
- Change: stages pull their upstream `Source` with a plain call (stdlib only, no API change), then let LLVM resolve interface calls by emitting vtables as constants.
- Decision requested: approve stage 1; approve measuring stage 2; no open questions remain.

## Status

Proposal, 2026-11-03, checked against `6242dcc1`. Replaces `streams-at-loop-speed.md` and `batched-streams.md`. Chinmay: keep the semantics, find a fast lowering, avoid breaking changes. Skeptical review: build stage 1; replace the MIR pass with the constant-vtable measurement; `for` lends the stream to its loop (decided).

## Problem

Measured, release `ms` at `6242dcc1`, 4-vCPU VM, 10M ints or 2M 28-byte lines, ns per item. Sources: `proposals/examples/streams-loop-lowering/{map_bench,lines_bench}.ms`.

| Loop | ns/item |
| --- | ---: |
| `for x in xs: total += x + 1` | 1.6 |
| `from_list(xs) \| map(f)`, `for .. in .wait()` (today) | 135 to 158 |
| the same chain as user `Source`s calling `up.next()` through the interface | 10 to 20 |
| the same chain with concrete types (static calls) | 2.0 |
| three `map` stages as user `Source`s through the interface | 22 |
| hand loop: `index_of_byte`, `slice`, `decode_utf8` per line | 49 |
| `lines(from_bytes(data))` (today) | 101 to 104 |
| a `Source` that cuts one line per `next`, through the interface | 51 |

- Waiting is already inside the leaf: `DescriptorSource.next` and `PipeSource.next` call `msrt_promise_wait` and park the task (`stdlib/io/io.ms:183`, `:284`). Every other stage is synchronous code wrapped in promises.
- `Through.next` calls `self.input.read().wait()` per item per stage: a promise, a deferred closure, a cell take and put (`io.ms:470`).
- `Mapper.feed` returns `[f(value)]`: one `List` allocation per item (`streams.ms:134`).
- Interface calls are not resolved: one `Source` over a list is 4.3 ns through the interface and 1.8 ns concrete. LLVM sees the vtable's address but not its contents, because data objects are declared `external global i8` (`crates/ms-clif/src/llvm_ir.rs:1577`).
- `Waiting.next` takes the source out of the runtime cell and puts it back per item (`io.ms:136`), so even a fully resolved pipeline is pulled through an opaque runtime call.

## Design

One rule: a stream is a chain of `Source`s, and the consumer's task pulls it by calling `next`. Only a leaf that touches the OS waits, inside its own `next`. A promise exists only when a caller asks for one with `read()`. Sync and async stay one type; a sync pipeline is plain calls.

### Stage 1: direct pull (stdlib only)

- `ReadStream[T]` (opaque) holds its source inline: `source: Source[T]?` and `cell: Int`, 0 until needed. `read()` moves the source into a new cell on first use and works as today.
- Internal `ReadStream.take_source() Source[T]` consumes the stream: the inline source, or a `CellSource` that reads through the cell when a `read()` already moved it there (today's semantics, including "a read is already waiting").
- `Through` holds `input: Source[A]` and calls `input.next()`. User `Transform`s keep `feed` returning `List[B]`: one list per input chunk, not per item. `pending` is read by index instead of reversed.
- `map` and `lines` stay pure `Transform`s (`Mapper`, `LineSplitter`) applied with `through` (Chinmay, 2026-11-03). Only `Through` changes.
- `collect`, `read_all`, `copy` call `take_source()` and loop on `next()`.
- `for x in s.wait()` lends `s` to the loop (Chinmay, 2026-11-03): `s.read()` or `s.close()` inside its own loop body is a checker error that points at a `while` with `read()`. `Waiting` holds the source for the whole loop and puts it back into the stream's cell at the end, on `break` and on an error, so `break` then `s.read()` keeps working. Removes the per-item cell round trip (about 10 ns) and the opaque call that would block stage 2.
- Measured on user-code prototypes (`Through` pulling directly, the same `Mapper` and `LineSplitter`): `map` 138 to 20 ns, `lines` 104 to 112 down to 74 to 80 ns. For comparison, `map` written as its own `Source` is 12 ns, and a hand loop that allocates each line is 47 to 54 ns. The remaining cost is one `List` per `feed` plus a vtable call per stage.

### Stage 2: constant vtables (measure first)

- Emit each vtable as an LLVM `constant` with its function pointers, 8-aligned so the ownership-tag mask folds, instead of `external global i8`. A call on an `iface.new` in the same function then folds to a direct call that LLVM can inline.
- General: every interface call benefits, including `stdout().write(...)`. Release builds only; Cranelift debug builds keep vtable calls.
- Unmeasured. Gate: the `map` row at least halves against stage 1 (20 ns). Hypothesis: once `feed` is inlined, LLVM can drop the one-item list (malloc and free of memory that does not escape); the concrete ceiling is 2.0 ns. If it misses, the gap is the payload heap box and nested boxes (`Through.input`, `Through.transform`), and a follow-up proposal would cover a MIR pass with repeated resolve-and-inline rounds; the module-wide field rule considered earlier does not hold for `a | map | map` and is dropped.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/io/io.ms` | inline source, `take_source`, `CellSource`, `Through` | stream e2e fixtures; new: `read()` then `through`, `break` then `read()`, error ends the loop and the source is back |
| `crates/ms-check` | `wait()` result lends its stream for the loop | conformance reject: `s.read()` inside `for x in s.wait()` |
| `stdlib/io/streams.ms` | `collect`, `read_all`, `copy` pull directly | existing `lines` and `map` fixtures unchanged |
| `crates/ms-clif/src/llvm_ir.rs` | stage 2: vtables as constants | release e2e on all three platforms |
| `bench/perf/` | new `streams` suite with the rows above | before/after against the latest baseline |
| `tools/leak-check.ms` | run on the stream fixtures | no new leaks |

## Alternatives

- **Do nothing:** `map` stays about 150 ns per item and `lines` 100.
- **Stage 1 only:** about 7 times faster on `map`, about 1.4 times on `lines`, no compiler work; one vtable call per stage per item and the cell round trip stay.
- **A MIR pass that resolves known implementations:** works in debug builds too, but needs repeated inline rounds, larger inline budgets for `Waiting.next` (128 instructions) and `Through.next` (156), and forwarding through heap boxes. Deferred until stage 2 is measured.
- **Generic stages over the concrete source type** (`Through[S, A, B]`): static calls without compiler work, but the source type would show in every `ReadStream` signature. Breaking; rejected.
- **`map` and `lines` as their own `Source`s:** `map` 12 ns instead of 20, but they would stop being pure transforms. Rejected by Chinmay.
- **A separate sync stream type, or batching items in the cell:** duplicates every stage, or adds rules for errors mid-batch. Rejected.

## Stages

1. Stage 1; check: `map` and `lines` rows move, all stream fixtures green on Linux, macOS, Windows.
2. Stage 2 as a measurement on a branch; it lands only if the `map` row at least halves and `bench/compile-time` does not regress.
