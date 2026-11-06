[Wiki](../index.md) › [Runtime and stdlib](index.md)

# Stream stages pull with plain calls; only leaves wait

Decision (Chinmay, 2026-11-03): sync and async streams stay one type, and pipelines must run at loop speed. Only a source that touches the system waits, inside its own `next` (`msrt_promise_wait` parks the task). `through` moves the input's source out of its cell (`source_of`) and calls `next` directly; `Waiting` holds the source for a whole `for` loop and puts it back at the end (`msrt_cells_out` says whether the stream is still there to take it). A promise exists only for `read()`. `map` and `lines` stay pure `Transform`s; do not turn them into `Source`s.

Rejected: a promise per stage per item (138 ns per `map` item), batching items in the cell, a separate sync stream type.

A stage that keeps or drops items (`filter`) is a `Transform` over `through`; one that must stop pulling early (`take`) is a `Source` over `source_of`, because a `Transform` cannot end its input. `fold` and `collect` are plain consumers.

Apply when: changing `stdlib/io/io.ms` streams, a stage in `stdlib/io/streams.ms`, or anything that reads a stream per item.
Evidence: [proposal](../../proposals/streams-loop-lowering.md), [fixture](../../tests/e2e/testdata/stdlib/stream-loops.ms), [suite](../../bench/perf/streams/README.md).
Verify: `ms test tests/e2e/testdata/stdlib/stream-loops.ms`.
