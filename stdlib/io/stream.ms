import Closeable from "@std/core.ms"
import Bytes, join from "@std/bytes.ms"
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
    msrt_cells_take_result,
    msrt_cells_put,
    msrt_cells_drop
) from "@std/internal/promises.ms"

# A new stream: next may wait.
export interface Source[T]:
    var fn next() T?!
    # Releases what the source owns; the stream calls it once, when it closes.
    var fn close() Unit!

# A stream of values over time. It owns its source, parked in a runtime cell so that a pending read carries only the
# cell's id; dropping the stream drops the source and whatever it owns.
export opaque type ReadStream[T]:
    cell: Int

# Runs one `next` of `source`, which the caller took out of its cell, and puts it back.
fn run[T](id: Int, cell: Int, source: Source[T]) Unit:
    var running = source
    let result = running.next()
    msrt_cells_put[Source[T]](cell, running)
    complete[T?](id, result)

# Runs the read `id` in the task that waits and completes it with the source's answer.
fn step[T](id: Int, cell: Int) Unit:
    match msrt_cells_take[Source[T]](cell):
        source:
            run[T](id, cell, source)
        none:
            complete[T?](
                id,
                error(Error("stream: a read is already waiting", kind: ErrorCategory.Closed))
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
        if let source = msrt_cells_take[Source[T]](self.cell):
            var closing = source
            try closing.close()
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

    var fn close() Unit!:
        msrt_streams_close(self.id)
        return ok(unit)

export fn stdin() ReadStream[Bytes]:
    return stream[Bytes](DescriptorSource(msrt_streams_open(0, 1)))

# A changed stream: never waits; appends zero or more items per input, and what it held back at the end.
export interface Transform[A, B]:
    var fn feed(value: A) List[B]!
    var fn finish() List[B]!

# Items a transform produced and the reader has not taken yet, newest first so `pop` moves the next one out.
type Through[A, B]:
    input: ReadStream[A]
    transform: Transform[A, B]
    pending: List[B]
    finished: Bool

impl Source[B] for Through[A, B]:
    var fn next() B?!:
        while true:
            if let item = self.pending.pop():
                return ok(item)
            if self.finished:
                return ok(none)
            let step = try self.input.read().wait()
            var produced: List[B] = []
            if let value = step:
                produced = try self.transform.feed(value)
            else:
                self.finished = true
                produced = try self.transform.finish()
            produced.reverse()
            self.pending = produced
        return ok(none)

    var fn close() Unit!:
        return self.input.close()

export fn through[A, B](input: ReadStream[A], transform: Transform[A, B]) ReadStream[B]:
    return stream[B](Through[A, B](input, transform, [], false))

# Lines of bytes, without their `\n` or `\r\n`, cut only at line ends; the unterminated last line comes at the end.
type LineSplitter:
    tail: Bytes

impl Transform[Bytes, String] for LineSplitter:
    var fn feed(value: Bytes) List[String]!:
        var out: List[String] = []
        let data = self.tail.concat(value)
        var start = 0
        while true:
            let end = data.index_of_byte(10, start)
            if end.is_none():
                break
            var stop = end.get()
            if stop > start and data.get(stop - 1, 0) == 13:
                stop -= 1
            let line = try data.slice(start, stop)
            out.append(line.decode_utf8().get(""))
            start = end.get() + 1
        self.tail = try data.slice(start, data.length())
        return ok(out)

    var fn finish() List[String]!:
        var out: List[String] = []
        if not self.tail.is_empty():
            out.append(self.tail.decode_utf8().get(""))
            self.tail = join([])
        return ok(out)

export fn lines(input: ReadStream[Bytes]) ReadStream[String]:
    return through[Bytes, String](input, LineSplitter(join([])))
