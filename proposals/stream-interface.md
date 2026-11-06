# Streams: one loop type, waiting inside the source

## Summary
- Problem: a stream stage costs about 20 ns per item against 1.6 for a hand loop, and iteration has three worlds (`Iterator`, `Iterable`, `ReadStream` behind `.wait()`).
- Change: `for` walks a `ReadStream` directly; `map`, `filter`, `take`, `lines` and `from_list` become direct pull stages; `Source` and `Sink` shrink; the runtime cell, `Waiting`, `read()` and `Through`'s buffer for these stages go.
- Decision requested: none. Chinmay approved the shape and asked for it to be built in the "Design the stream interface" thread, 2026-11-06.

## Status
Proposal, 2026-11-06, checked against `a0dbdcb2`. Direction (Chinmay): no overhead from streams; one type for sync and waiting streams; wait only at the source; cleanup stays in `Closeable`; `ReadStream` and `WriteStream` stay concrete `Closeable` types that wrap a `Source` or `Sink`; `for` binds `T` with implicit `try`; no read-ahead; `Promise.with` stays; back pressure; `Source` and `Sink` simplified. Iterator and Iterable removal, with `Queue`, `Deque` and `PriorityQueue` becoming `Source`s, is a separate PR after this one.

## Problem
`bench/perf/streams` on main (ns per item): `stream-map` 21.6, `stream-map3` 40.3, `stream-collect` 18.8, `stream-lines` 57.7, hand loop 1.6. Callgrind on `from_list | map`: 99 of 114 instructions are in `Through.next` (a per-stage `List`, `Result`/`Option` wrapping, a runtime cell round trip). Waiting already happens inside `next` (`DescriptorSource.next` calls `msrt_promise_wait`; tasks are stackful), so no type needs to say "async".

## Design
```manuscript
export interface Source[T]:                  // implement to make a stream; wrap with stream(...)
    var fn next() T?!                        // may wait inside; none at the end
    var fn close() Unit!
export interface Sink[T]:                    // implement to make a writer; wrap with writer(...)
    var fn write(value: T) Unit!             // waits while the sink is full: back pressure
    var fn flush() Unit!                     // returns once everything written has drained
    var fn close() Unit!

for line in file.reader() | lines | map(parse):   // item is T; a failed next leaves with its error, as `try`
    process(line)
```
- `ReadStream[T]` and `WriteStream[T]` are records that own their source or sink and implement `Closeable`; the checker recognises the standard `ReadStream` for `for`. `ReadStream` gains `next()`, a direct call (no cell, no promise); `read()`, `wait()` and `Waiting` go. `WriteStream.flush()` blocks. `close` closes the source or sink once and replaces it with an empty one, so a native handle held by the record is released at once.
- `for x in s` over a `ReadStream` expands like `Iterator` (`check_iterator_for`) to `while true: if let x = try s.next(): body else: break`; the enclosing function must return a `Result`. A variable advances in place; any other expression is held in a hidden `var` that closes at scope end.
- A stage is a `Source` over its input `ReadStream`, closing it on close. `lines` pulls (held chunk and cursor, no output buffer); `filter` no longer needs `Clonable`. A whole pipeline is limited by running its loop in a promise with `PromiseOptions`. Push codecs (JSON, CSV, SSE, base64, tar, compression) keep `Transform` and `through`; `step` and `finish` now append to a `List[B]` instead of a `WriteStream`.
- Back pressure: a stage pulls its input only inside its own `next`. `write` waits once the sink holds more than its high-water mark (pipe: `capacity`; descriptors: the runtime's write queue limit); nothing else buffers items, and there is no read-ahead stage.
- Promises stay on waiting-source operations (`read_file`, `connect`, `Listener.accept`) and `promise(fn: ...)`. Cancel and timeout wake a task parked in `msrt_promise_wait` inside `next` as cancelled; fixtures pin a pipe loop under a time limit and a cancel switch.

## Components touched
| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `stmts.rs`, `types.rs` | `for` over `ReadStream` (`Builtin::ReadStream`) | new checker tests: `break`, `try`, early return, a call expression held by the loop |
| `stdlib/io/io.ms`, `streams.ms` | new core, stages, `Sink` renames | `tests/e2e/testdata/stdlib/stream-loops.ms` |
| `stdlib/os/fs.ms`, `net/*.ms`, `os/process.ms`, `os/time.ms`, `data/*`, `crypto*`, `test/iotest.ms` | sinks `write`/`flush`, loops without `.wait()`, `Transform` over `List` | stdlib e2e fixtures |
| `ms-rt` `cells.rs`, `ms-lower` `natiface.rs`, `ms-check/src/stdlib.rs` | drop `msrt_cells_*` and the stream rows | `make conform` |
| docs, `bench/`, `tests/`, `ms-repo-check/stream_names.rs`, wiki | `.wait()` and `put`/`drain` examples; supersede `stream-stages-pull-with-plain-calls` | `make repo-check`, `make docs` |

## Alternatives considered
- Do nothing: stages stay 10x a loop and `.wait()` stays the boundary.
- Fix `Through` only (map as a `Source`): 21.6 to 14.7 ns, still two worlds; rejected earlier.
- Interfaces `ReadStream`/`WriteStream` owning resources: needs a `close` op on them (works, proven by a spike) or a new ownership marker; opaque types need neither.
- Owner and borrowed views: best fit for one owner, but needs borrow-holding types the checker lacks.
- `Promise[T]` items for waiting sources: a promise per chunk and a conversion rule.
- Compiler fusion of `for` over pipelines: new feature with unspecified `break`/close semantics; not needed at about 2 ns per stage.
- Interface devirtualization: measured no gain, LLVM already resolves these calls in release builds (#2717).

## Measurements
User-level prototype of this shape on this checkout, 5 M items, ns per item: hand loop 1.6 to 2.6; 1 `map` 3.3 to 4.1; 3 `map` 9.5 to 11; `map` + `filter` 4.9 to 5.7. Dropping the `Result` changed nothing; assembly shows an indirect call and a write-back of the stage record per `next`. The ported stdlib measures `stream-map` 10 to 12, `stream-map3` 16 to 21, `stream-collect` 8 to 10, `stream-lines` 41 to 47 (see `bench/perf/streams/README.md`): about twice as fast as before, but short of the prototype because each stage still pays a `ReadStream` wrapper call and a closure call. Closing that gap is separate work.

## Risks
- Migration size: 17 stdlib files, 104 files mention `ReadStream`, about 40 `.wait()` loops and 150 `.read()` uses. The port also found and fixed a lowering bug: an owned temporary held across a later `try` in the same call was copied instead of moved into a consumed parameter (`ms-lower` `call.rs`; fixture `owned-temp-before-try-argument.ms`).
- `for` requires a `Result`-returning function; `main() Unit` uses an explicit `next()` loop.
- A waiting `write` waits above a high-water mark: pipe `capacity` (fixture `pipe.ms`) and 1 MiB for descriptors (checked by hand with a slow child process; no portable fixture).
- Close order and early exit need fixtures, and Linux, macOS and Windows stay at parity.
