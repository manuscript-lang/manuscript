import (
	Closeable from "@std/core.ms",
	Duration from "@std/time.ms",

	msrt_cancel_fire,
	msrt_cancel_fired,
	msrt_cancel_free,
	msrt_cancel_new,
	msrt_promise_cancel,
	msrt_promise_defer,
	msrt_promise_done,
	msrt_promise_drop,
	msrt_promise_fault_report,
	msrt_promise_limit,
	msrt_promise_new,
	msrt_promise_on_cancel,
	msrt_promise_put,
	msrt_promise_run_unstarted,
	msrt_promise_start,
	msrt_promise_start_here,
	msrt_promise_start_spread,
	msrt_promise_take,
	msrt_promise_wait,
	msrt_promise_wait_any from "@std/internal/promises.ms",
)

// Promises: operations whose results are taken once with `wait()`.
//
// `promise(fn: ...)` starts work eagerly on a thread the runtime picks; `wait()` takes its result. Stream reads may
// defer work until the wait. Any function can wait internally, even if it returns a
// value directly. Dropping a promise that has not finished cancels it and waits for it
// to end, so work you start never outlives the values it uses. A promise only reads
// what it captures: concurrent code never changes a shared value (to change shared
// state, give it one owner and send it values over a `pipe`).
//
// <!-- manuscript-example: {"mode":"fragment"} -->
// ```manuscript
// config := read_file("config.json")  // Promise[Bytes], already running
// words := promise(
//     fn: count_words(text), options: PromiseOptions(timeout: 5.seconds())
// )  // may run on another thread, ends with ETIMEDOUT after 5 s
// bytes := config.wait()?
// total := words.wait()?
// ```

// An operation with one result. `wait` takes it once; a stream read may defer work
// until the wait. Dropping an unfinished promise cancels it and waits for it to end; an
// unused promise is a warning.
export opaque type Promise[T]:
	// The runtime slot of this promise: a generation and an index, never reused while
	// this id is live.
	id: Int

// Waits for the result and moves it out. Errors: the operation's own error; `EIO`
// (a fault inside, with its report in `details["report"]`); `ECANCELED`; `EBADF`
// (an earlier wait already took the result); `ETIMEDOUT` once the promise's
// `timeout` option has passed, which also cancelled the work.
fn Promise[T].wait() T!:
	code := msrt_promise_wait(self.id, -1)
	if code == 0: return taken_result[T](self.id)

	return error(failure(self.id, code))

// Applies `options` to a promise made elsewhere (`read_file`, `fetch`, `sleep`,
// `exec`) and returns it, so
// `read_file(path).with(options: PromiseOptions(timeout: 5.seconds())).wait()` bounds the read. The timeout counts from now.
// A provided cancel signal replaces the previous signal.
fn Promise[T].with(options: PromiseOptions = PromiseOptions()) Promise[T]:
	limit(self.id, options)
	return self

// Asks the work to stop at its next wait; `wait` then reports `ECANCELED`. It
// returns at once, and dropping the promise joins the work. A finished promise is
// unchanged.
fn Promise[T].cancel() Unit:
	msrt_promise_cancel(self.id)

// Whether the work has finished, however it ended. It never waits.
fn Promise[T].done() Bool:
	return msrt_promise_done(self.id)

// Dropping a promise ends it: unfinished work is cancelled and waited for, and a
// result nobody took is dropped.
fn var Promise[T].close() Unit!:
	msrt_promise_drop(self.id)

// Which thread runs a promise's work.
export enum Placement:
	// A thread the runtime picks: queued on the calling thread for an idle one to take.
	Any
	// The least loaded thread at once, starting a thread when the limit allows. For
	// long-lived work that should use every core, such as one serving worker per core.
	Spread
	// A task on the calling thread. For work that uses values bound to this thread (a
	// network handle, a connection, a socket) and only waits (on a file, a socket, a
	// child process): work that computes blocks its thread.
	Here

// What bounds a promise, fixed when it is made: `timeout` counts from construction and
// is enforced whether or not anyone waits; when it passes the work is cancelled and
// `wait` reports `ETIMEDOUT`. A negative timeout is no time at all.
export type PromiseOptions:
	// How long the work may run, counted from construction; none means no limit.
	timeout: Duration? = none
	// When this signal's `Cancel` fires, the work is cancelled and `wait` reports
	// `ECANCELED`. Applying a signal to an existing promise replaces its previous
	// signal; none leaves it unchanged.
	cancel: Signal? = none
	// Which thread runs the work.
	placement: Placement = Placement.Any

// One switch that cancels every promise made with its `signal()`. `cancel()` never
// waits; the work stops at its next wait and `wait` reports `ECANCELED`. Dropping the
// switch does not cancel anything: promises made with its signals keep running.
export opaque type Cancel:
	// The runtime slot of this switch: a generation and an index.
	id: Int

// A handle for `PromiseOptions(cancel: ...)`; make as many as you need.
fn Cancel.signal() Signal:
	return Signal(id: self.id)

// Cancels every promise made with a signal of this switch, now and later. Safe to
// call again.
fn Cancel.cancel() Unit:
	msrt_cancel_fire(self.id)

// Frees the switch. Promises made with its signals keep running; they just cannot
// be cancelled by it any more.
fn var Cancel.close() Unit!:
	msrt_cancel_free(self.id)

// A new switch that has not fired.
export fn cancel_switch() Cancel:
	return Cancel(id: msrt_cancel_new())

// A copyable handle to a `Cancel`, passed in `PromiseOptions`. Once its `Cancel` fires
// it reads as cancelled for good, even after the `Cancel` is closed or dropped; a
// `Cancel` that never fired reads as not cancelled once it is gone.
export opaque type Signal:
	// The slot of the `Cancel` it belongs to; a freed slot never matches.
	id: Int

// Whether the switch has fired, for work that loops without waiting.
fn Signal.cancelled() Bool:
	return msrt_cancel_fired(self.id)

// A limit in nanoseconds, or -1 for none. A negative duration is no time at all, not
// "none".
fn nanos(limit: Duration?) Int:
	if own := limit:
		total := own.to_nanoseconds()
		if total < 0: return 0

		return total

	return -1

// The error a `wait` that did not produce a result reports, from the runtime outcome
// code of the promise `id`.
fn outcome(id: Int, code: Int) Error:
	if code == 2: return Error("promise: timed out", kind: "ETIMEDOUT")
	if code == 3: return Error("promise: cancelled", kind: "ECANCELED")
	if code == 4: return Error("promise: the result was already taken", kind: "EBADF")

	report := msrt_promise_fault_report(id)
	return Error(
		"promise: fault: " + report,
		kind: "EIO",
		details: {"report": report.clone()},
	)

// Applies `options` to the promise `id`.
fn limit(id: Int, options: PromiseOptions) Unit:
	if options.timeout.is_some():
		msrt_promise_limit(id, nanos(options.timeout))
	if signal := options.cancel:
		msrt_promise_on_cancel(id, signal.id)

// Applies `options` to a promise in place, for an owner that keeps the promise (a
// server's accept loop). The timeout counts from now; a provided cancel signal replaces
// the previous signal. `with` is the chaining form.
export fn set_options[T](
	target: Promise[T],
	options: PromiseOptions = PromiseOptions(),
) Unit:
	limit(target.id, options)

// The result in the slot of `id`, moved out; `EBADF` when it is gone.
fn taken_result[V](id: Int) V!:
	if value := msrt_promise_take[V](id): return ok(value)
	return error(outcome(id, 4))

// The error in the slot of `id`, moved out.
fn taken_error(id: Int) Error:
	if cause := msrt_promise_take[Error](id): return cause
	return outcome(id, 4)

// The error of a `wait` whose runtime outcome `code` is not success: the operation's
// own error for code 1, else the outcome's. One function for every failure keeps the
// error construction out of `wait`, whose frame stays on the stack while a task parks.
fn failure(id: Int, code: Int) Error:
	if code == 1: return taken_error(id)
	return outcome(id, code)

// Stores how `entry` ended in the promise `id`.
export fn complete[U](id: Int, result: U!) Unit:
	match result:
		ok(value):
			msrt_promise_put(id, value, 0)
		error(cause):
			msrt_promise_put(id, cause, 1)

// Runs `entry` as a promise and returns it. The closure follows the capture rules: a
// promise that is returned or kept owns what `entry` captures (bind a `.clone()` first
// to keep a value), and one that stays in the function reads its captures in place, so
// they must outlive it and cannot change while it lives. A fault inside ends only this
// promise: `wait` reports it as `EIO`. `options.placement` picks the thread.
export fn promise[U](
	entry: fn() U!,
	options: PromiseOptions = PromiseOptions()
) Promise[U]:
	id := msrt_promise_new()

	match options.placement:
		Placement.Any:
			msrt_promise_start(id, fn: complete(id, entry()))
		Placement.Spread:
			msrt_promise_start_spread(id, fn: complete(id, entry()))
		Placement.Here:
			msrt_promise_start_here(id, fn: complete(id, entry()))

	limit(id, options)
	return Promise[U](id: id)

// Waits for every promise and returns the results in order. The first promise to fail,
// in time rather than list order, ends the wait: the promises still running are
// cancelled and waited for before `wait_all` returns its error.
export fn wait_all[T](promises: List[Promise[T]]) List[T]!:
	var pending = promises
	count := pending.length()
	var slots: List[T!] = []
	var taken: List[Bool] = []

	for at in 0..count:
		slots.append(error(Error("promise: not finished")))
		taken.append(false)

	// In list order, take what is finished. When the next one is not, block until
	// anything finishes and take everything that has, so a failure behind a slow
	// promise ends the wait without waiting for the slow one.
	var head = 0

	while head < count:
		if taken[head]:
			head += 1
		else if msrt_promise_run_unstarted(pending[head].id) or pending[head].done():
			value := pending[head].wait()?
			slots[head] = ok(value)
			taken[head] = true
			head += 1
		else:
			var ids: List[Int] = []
			for at in head..count:
				if not taken[at]:
					ids.append(pending[at].id)
			msrt_promise_wait_any(ids, -1)

			for at in head..count:
				if not taken[at] and pending[at].done():
					value := pending[at].wait()?
					slots[at] = ok(value)
					taken[at] = true

	var reversed: List[T] = []
	for at in 0..count:
		if slot := slots.pop():
			reversed.append(slot?)

	var results: List[T] = []
	for at in 0..count:
		if value := reversed.pop():
			results.append(value)
	return ok(results)

// Waits for the first promise to finish and returns its result; the others are
// cancelled and waited for. Errors as
// `wait` does; an empty list is an error.
export fn wait_first[T](promises: List[Promise[T]]) T!:
	var pending = promises
	if pending.is_empty(): return error(Error("promise: nothing to wait for"))

	var ids = pending.map(fn p: p.id)
	which := msrt_promise_wait_any(ids, -1)
	return pending[which].wait()

// A promise whose work runs in the task that first waits on it, on that task's stack,
// with no task of its own. The work may wait itself. `make` receives the new promise's
// id and returns the work; it ends with `complete(id, ...)`. For stream
// implementations: dropping the promise first discards the work unrun.
export fn deferred[U](work: fn(Int) Unit) Promise[U]:
	id := msrt_promise_new()
	msrt_promise_defer(id, fn: work(id))
	return Promise[U](id: id)

// A promise over the runtime promise `id` that a native operation completes (a stream
// read or flush).
export fn adopt[U](id: Int) Promise[U]:
	return Promise[U](id: id)
