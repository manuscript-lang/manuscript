[Wiki](../index.md) › [Runtime and stdlib](index.md)

# Streams wait in the source and stages pull directly

Decision (Chinmay, 2026-11-06, superseding 2026-11-03): one stream type for memory and waiting sources, because tasks are stackful and a source waits inside its own `next` (`msrt_promise_wait` parks only that task). `ReadStream[T]` owns a `Source[T]` (`next`, `close`) and `WriteStream[T]` owns a `Sink[T]` (`write`, `flush`, `close`); both are `Closeable`. `for x in stream` binds `T` and leaves the loop with a failed read's error, as `?` would. There is no `read()`, `wait()`, `Waiting`, runtime cell, `put`, `drain` or `buffered`.

- Stages (`map`, `filter`, `take`, `lines`) are `Source`s over their input `ReadStream` and pull it only inside their own `next`. Back pressure is therefore pull-based; `write` waits once a sink holds more than its high-water mark (pipe: `capacity`; descriptors: 1 MiB). No read-ahead stage exists by decision.
- A failed read delivers no item. `take` preserves its remaining budget when its input returns an error, so a caller retrying `next` can still receive the requested items; decrementing before the read silently truncated retries. The [stage tests](../../tests/e2e/testdata/stdlib/stream-filter-take-fold.ms) cover the last slot, repeated errors through `filter` and `map`, and no reads after the cap.
- Closing a stream closes its source once and then replaces it with an empty one. The replacement matters: a native handle counted with `Rc` closes only when the source record is dropped, so a closed stream that kept its source kept the socket open.
- Cancellation and time limits are not stream API: run the loop in a promise with `PromiseOptions`. There is no per-item timeout stage by decision.
- Push codecs (JSON, CSV, SSE, base64, tar, compression) keep `Transform` and `through`; `step` and `finish` append to a `List[B]`.
- Rejected: a promise per stage per item, `Promise[T]` items for waiting sources, `Iterator`-shaped stream with `Result` items, owner-and-view streams (the checker cannot hold a borrowed owner), interface `ReadStream` that owns resources (needs a `close` operation or a new ownership marker).

Apply when: changing `stdlib/io/io.ms` or `streams.ms`, a `Source` or `Sink` implementation, or a loop over a stream.
Evidence: [proposal](../../proposals/stream-interface.md), [cancel fixture](../../tests/e2e/testdata/stdlib/stream-cancel.ms), [loops fixture](../../tests/e2e/testdata/stdlib/stream-loops.ms), [suite](../../bench/perf/streams/README.md).
Verify: `ms test tests/e2e/testdata/stdlib/stream-loops.ms tests/e2e/testdata/stdlib/stream-cancel.ms`.
