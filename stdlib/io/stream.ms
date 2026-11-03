import Closeable from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import Promise, deferred, complete from "@std/concurrency/promise.ms"
import (
    msrt_promise_take,
    msrt_promise_wait,
    msrt_promise_drop,
    msrt_streams_open,
    msrt_streams_read,
    msrt_streams_error,
    msrt_streams_close,
    msrt_cells_new,
    msrt_cells_take,
    msrt_cells_put,
    msrt_cells_drop
) from "@std/internal/promises.ms"

# A new stream: next may wait.
export interface Source[T]:
    var fn next() T?!

# A stream of values over time. It owns its source, parked in a runtime cell so that a pending read carries only the
# cell's id; dropping the stream drops the source and whatever it owns.
export opaque type ReadStream[T]:
    cell: Int

# Runs one `next` of the source parked in `cell`, in the task that waits, and completes the read `id` with its answer.
fn step[T](id: Int, cell: Int) Unit:
    if let source = msrt_cells_take[Source[T]](cell):
        var running = source
        let result = running.next()
        msrt_cells_put[Source[T]](cell, running)
        complete[T?](id, result)
        return

    complete[T?](
        id, error(Error("stream: a read is already waiting", kind: ErrorCategory.Closed))
    )

impl ReadStream[T]:
    # One step, started now and run where it is waited; none at the end.
    var fn read() Promise[T?]:
        let cell = self.cell
        let work = fn(id: Int) Unit: step[T](id, cell)
        return deferred[T?](work)

impl Closeable for ReadStream[T]:
    # Drops the source and everything it owns. A read in flight ends with an error.
    var fn close() Unit!:
        msrt_cells_drop(self.cell)
        return ok(unit)

export fn stream[T](source: Source[T]) ReadStream[T]:
    return ReadStream[T](cell: msrt_cells_new[Source[T]](source))

export type DescriptorSource:
    id: Int

impl Source[Bytes] for DescriptorSource:
    var fn next() Bytes?!:
        let p = msrt_streams_read(self.id)
        let code = msrt_promise_wait(p, -1)
        let chunk = msrt_promise_take[Bytes](p)
        msrt_promise_drop(p)
        if let data = chunk:
            return ok(data)
        let message = msrt_streams_error(self.id)
        if message.length() > 0:
            return error(Error(message, kind: ErrorCategory.Failed))
        return ok(none)

export fn stdin() ReadStream[Bytes]:
    return stream[Bytes](DescriptorSource(msrt_streams_open(0, 1)))

export fn debug_direct() Int:
    var s = DescriptorSource(msrt_streams_open(0, 1))
    let r = s.next()
    if r.is_error():
        return -1
    if let b = r.get():
        return b.length()
    return -2
