// ms: allow_effect std.clock.read

import (
	Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	ReadStream, WriteStream, pipe from "@std/io/io.ms",
)

// Bridges a stream that only one thread may touch to the other threads.

// Internal: the writer `forward` returns. Writes go to a pipe; a task on the thread
// that made it copies the pipe to the real stream, and closing waits for that copy.
type Forwarder[T]:
	inbox WriteStream[T]
	task Promise[Int]

fn var Forwarder[T].write(move value T) Void!:
	return self.inbox.write(value)

fn var Forwarder[T].flush() Void!:
	return self.inbox.flush()

fn move Forwarder[T].close() Void!:
	// A copy that failed (the client left) was already reported to writers as EBADF, so
	// closing is not a second failure.
	_closed := self.inbox.close()
	_copied := self.task.wait()
	return ok()

// Internal: moves every item of `mail` to `out`, then flushes it.
fn pump[T](var mail ReadStream[T], var out WriteStream[T]) Int!:
	var count = 0

	for item in mail:
		out.write(item)?
		count += 1

	out.flush()?
	return ok(count)

// Returns a writer that any thread may use for `out`, which only the calling thread may
// touch (a websocket or connection end, for example). Writes queue in a pipe of
// `capacity` values, and a task on this thread copies them to `out`, so a state owner on
// another thread can push to it. Closing the writer ends the copy and then closes
// `out`.
export fn forward[T](move out WriteStream[T], capacity Int = 16) WriteStream[T]:
	var queue = pipe[T](capacity)
	var mail = queue.reader()
	inbox := queue.writer()
	task := promise(
		fn: pump(mail, out),
		options: PromiseOptions(placement: Placement.Here)
	)
	return WriteStream[T](Forwarder[T](inbox, task))
