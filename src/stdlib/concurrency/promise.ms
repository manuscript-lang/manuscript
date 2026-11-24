import (
	Closeable, panic from "@std/core.ms",
	Duration from "@std/time.ms",

	Slot,
	msrt_cancel_fire,
	msrt_cancel_fired,
	msrt_cancel_free,
	msrt_cancel_new,
	msrt_group_free,
	msrt_group_join,
	msrt_group_new,
	msrt_group_next,
	msrt_group_poll,
	msrt_promise_cancel,
	msrt_promise_close,
	msrt_promise_defer,
	msrt_promise_done,
	msrt_promise_drop,
	msrt_promise_fault_report,
	msrt_promise_limit,
	msrt_promise_on_cancel,
	msrt_promise_put,
	msrt_promise_run_watched,
	msrt_promise_start,
	msrt_promise_start_here,
	msrt_promise_start_idle,
	msrt_promise_start_spread,
	msrt_promise_take,
	msrt_promise_wait,
	msrt_promise_wait_any from "@std/internal/promises.ms",
)

// Promises: operations whose results are taken once with `wait()`.
//
// `promise(fn: ...)` starts work eagerly on a thread the runtime picks, and `wait()`
// takes its result. Stream reads may defer work until the wait. Any function can wait
// internally, even if it returns a value directly.
//
// Dropping a promise that has not finished cancels it and waits for it to end, so work
// you start never outlives the values it uses. A promise only reads what it captures,
// so concurrent code never changes a shared value. To change shared state, give it one
// owner and send it values over a `pipe`.
//
// <!-- manuscript-example: {"mode":"fragment","given":["text: String"]} -->
// ```manuscript
// import PromiseOptions, promise from "@std/concurrency/promise.ms"
// import read_file from "@std/os/fs.ms"
//
// fn count_words(text: String) Int!:
//     return ok(text.split(" ").length())
//
// config := read_file("config.json")  // Promise[Bytes], already running
// words := promise(
//     fn: count_words(text), options: PromiseOptions(timeout: 5.seconds())
// )  // may run on another thread, ends with ETIMEDOUT after 5 s
// bytes := config.wait()?
// total := words.wait()?
// print(f"{bytes.length()} bytes, {total} words")
// ```

// An operation with one result. `wait` takes the result once, and a stream read may
// defer its work until the wait. Dropping an unfinished promise cancels it and waits
// for it to end. A promise that is never used or waited on is a warning.
export opaque type Promise[T]:
	// The runtime slot of this promise: a generation and an index, never reused while
	// this id is live.
	id: Int

// Waits for the result and moves it out. It can return:
//
// - the operation's own error;
// - `EIO`, when the work faulted (the report is in `details["report"]`);
// - `ECANCELED`, when the work was cancelled;
// - `EBADF`, when an earlier wait already took the result;
// - `ETIMEDOUT`, once the promise's `timeout` option has passed, which also cancelled
//   the work.
fn Promise[T].wait() move T!:
	code := msrt_promise_wait(self.id, -1)
	if code == 0: return taken_result[T](self.id)

	return error(failure(self.id, code))

// Applies `options` to a promise made elsewhere (`read_file`, `fetch`, `sleep`,
// `exec`) and returns it, so
// `read_file(path).with(options: PromiseOptions(timeout: 5.seconds())).wait()` bounds
// the read. The timeout counts from now. A provided cancel signal replaces the previous
// one.
fn Promise[T].with(options: PromiseOptions = PromiseOptions()) Promise[T]:
	limit(self.id, options)
	return self

// Asks the work to stop at its next wait; `wait` then reports `ECANCELED`. It
// returns at once, and dropping the promise waits for the work to end. A finished
// promise is unchanged.
fn Promise[T].cancel() Void:
	msrt_promise_cancel(self.id)

// Reports whether the work has finished, however it ended. It never waits.
fn Promise[T].done() Bool:
	return msrt_promise_done(self.id)

// Dropping a promise ends it: unfinished work is cancelled and waited for, and a
// result nobody took is dropped, which closes what it holds.
fn move Promise[T].close() Void!:
	if msrt_promise_close(self.id):
		_leftover := msrt_promise_take[Slot[T]](self.id)
		msrt_promise_drop(self.id)

// Which thread runs a promise's work.
export enum Placement:
	// A thread the runtime picks: queued on the calling thread for an idle one to take.
	Any
	// The least loaded thread at once, starting a thread when the limit allows. For
	// long-lived work that should use every core, such as one serving worker per core.
	Spread
	// A task on the calling thread. Use it for work that uses values bound to this
	// thread (a network handle, a connection, a socket) and only waits (on a file, a
	// socket, a child process). Work that computes blocks the thread.
	Here

// What bounds a promise, fixed when it is made. `timeout` counts from construction and
// is enforced whether or not anyone waits; when it passes, the work is cancelled and
// `wait` reports `ETIMEDOUT`. A negative timeout means no time at all.
export type PromiseOptions:
	// How long the work may run, counted from construction; `null` means no limit.
	timeout: Duration? = null
	// When this signal's `Cancel` fires, the work is cancelled and `wait` reports
	// `ECANCELED`. Applying a signal to an existing promise replaces its previous
	// signal; null leaves it unchanged.
	cancel: Signal? = null
	// Which thread runs the work.
	placement: Placement = Placement.Any

// A switch that cancels every promise made with its `signal()`. `cancel()` never
// waits; the work stops at its next wait and `wait` reports `ECANCELED`. Dropping the
// switch does not cancel anything: promises made with its signals keep running.
export opaque type Cancel:
	// The runtime slot of this switch: a generation and an index.
	id: Int

// Returns a handle for `PromiseOptions(cancel: ...)`. Make as many as you need.
fn Cancel.signal() Signal:
	return Signal(id: self.id)

// Cancels every promise made with a signal of this switch, now and later. Calling it
// again is safe.
fn Cancel.cancel() Void:
	msrt_cancel_fire(self.id)

// Frees the switch. Promises made with its signals keep running, but the switch can no
// longer cancel them.
fn move Cancel.close() Void!:
	msrt_cancel_free(self.id)

// Returns a new switch that has not fired.
export fn cancel_switch() Cancel:
	return Cancel(id: msrt_cancel_new())

// A copyable handle to a `Cancel`, passed in `PromiseOptions`. Once its `Cancel` has
// fired, it reads as cancelled for good, even after the `Cancel` is closed or dropped.
// A `Cancel` that never fired reads as not cancelled once it is gone.
export opaque type Signal:
	// The slot of the `Cancel` it belongs to; a freed slot never matches.
	id: Int

// Reports whether the switch has fired. Use it in work that loops without waiting.
fn Signal.cancelled() Bool:
	return msrt_cancel_fired(self.id)

// Internal: a limit in nanoseconds, or -1 for null. A negative duration means no time
// at all, not "null".
fn nanos(limit: Duration?) Int:
	own := limit

	if own != null:
		total := own.to_nanoseconds()
		if total < 0: return 0

		return total

	return -1

// Internal: the error that a `wait` reports when it produced no result, from the
// runtime outcome code of the promise `id`.
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

// Internal: applies `options` to the promise `id`.
fn limit(id: Int, options: PromiseOptions) Void:
	if options.timeout != null:
		msrt_promise_limit(id, nanos(options.timeout))

	signal := options.cancel
	if signal != null:
		msrt_promise_on_cancel(id, signal.id)

// Applies `options` to a promise in place, for an owner that keeps the promise (such
// as a server's accept loop). The timeout counts from now, and a provided cancel
// signal replaces the previous one. `with` is the chaining form.
export fn set_options[T](
	target: Promise[T],
	options: PromiseOptions = PromiseOptions(),
) Void:
	limit(target.id, options)

// Internal: the result in the slot of `id`, moved out; `EBADF` when it is gone.
fn taken_result[V](id: Int) V!:
	taken := msrt_promise_take[Slot[V]](id)
	if taken != null: return ok(taken.value)

	return error(outcome(id, 4))

// Internal: the error in the slot of `id`, moved out.
fn taken_error(id: Int) Error:
	cause := msrt_promise_take[Error](id)
	if cause != null: return cause

	return outcome(id, 4)

// Internal: the error of a `wait` whose runtime outcome `code` is not success: the
// operation's own error for code 1, otherwise the outcome's. One function for every
// failure keeps the error construction out of `wait`, whose frame stays on the stack
// while a task parks.
fn failure(id: Int, code: Int) Error:
	if code == 1: return taken_error(id)
	return outcome(id, code)

// Stores how the work ended (its result or error) in the promise `id`.
export fn complete[U](id: Int, move result: U!) Void:
	match result:
		ok(value): msrt_promise_put(id, value, 0)
		error(cause): msrt_promise_put(id, cause, 1)

// Starts `entry` like a `Placement.Here` promise, except that when no other task is
// running it runs in the task that first waits on it, which saves the cost of a task
// of its own. Use it for operations that do not block for long, such as reading a
// file. The work follows the capture rules of `promise`.
export fn promise_when_idle[U](entry: fn() U!, site: String = caller_frame()) Promise[U]:
	id := msrt_promise_start_idle(fn id: complete(id, entry()), site)
	return Promise[U](id: id)

// Returns where the call that omitted this argument is, as a fault report shows a
// frame: `file:line in function`. Use it only as a parameter default, in a function
// that is called directly; the compiler fills it in as a constant at each call.
export fn caller_frame() String:
	panic("caller_frame() is only valid as a parameter default")

// Runs `entry` as a promise and returns the promise. The closure follows the capture
// rules. A promise that is returned owns what `entry` captures and closes or drops it
// when its work ends (bind a `.clone()` first to keep a value). A promise that stays in
// the function reads its captures in place, so they must outlive it and cannot change
// while it lives; to give it a resource, move the resource into a helper that returns
// the promise. A fault
// inside ends only this promise, and `wait` reports it as `EIO`. `options.placement`
// picks the thread. `site` is the line a fault report gives after `task started by:`;
// leave it out and it is the line of this call. A helper that starts a promise for its
// caller takes `site: String = caller_frame()` itself and passes it on.
export fn promise[U](
	entry: fn() U!,
	options: PromiseOptions = PromiseOptions(),
	site: String = caller_frame()
) Promise[U]:
	id := match options.placement:
		Placement.Any: msrt_promise_start(fn id: complete(id, entry()), site)
		Placement.Spread: msrt_promise_start_spread(fn id: complete(id, entry()), site)
		Placement.Here: msrt_promise_start_here(fn id: complete(id, entry()), site)

	limit(id, options)
	return Promise[U](id: id)

// Internal: promises of this thread watched together; `next` reports which finished,
// each once.
opaque type WaitSet:
	// The runtime group.
	id: Int

fn move WaitSet.close() Void!:
	msrt_group_free(self.id)

// Internal: the error `wait_all` reports when the run of the promise at `head` ended
// in a failure: the error of the first promise of the set to fail.
fn first_failure[T](
	set: Int,
	pending: List[Promise[T]],
	taken: List[Bool],
	head: Int,
) Error:
	var at = msrt_group_poll(set)

	while at >= 0:
		if not taken[at] and at != head:
			result := pending[at].wait()

			match result:
				ok(_): at = msrt_group_poll(set)
				error(cause): return cause.clone()
		else:
			at = msrt_group_poll(set)

	return Error("promise: cancelled")

// Internal: the results of `msrt_promise_run_watched`: nothing ran, a promise ran, or
// a failure ended the run.
fn ran_nothing(result: Int) Bool: result == 0

fn run_interrupted(result: Int) Bool: result == 2

// Internal: the result of `msrt_group_join` when some promises belong to another
// thread and are polled.
fn joined_partly(result: Int) Bool: result == 2

// Waits for every promise and returns the results in order. The first promise to fail,
// in time rather than list order, ends the wait: the promises still running are
// cancelled and waited for before `wait_all` returns that error.
export fn wait_all[T](move promises: List[Promise[T]]) move List[T]!:
	var pending = promises
	count := pending.length()
	var slots: List[T!] = []
	var taken: List[Bool] = []
	var members: List[Int] = []
	set := WaitSet(id: msrt_group_new())

	for at in 0..count:
		slots.append(error(Error("promise: not finished")))
		taken.append(false)
		members.append(pending[at].id)

	// Go through the list in order and take what is finished. A promise that has not
	// started runs here. When it first waits, the rest join the set (`mode` 1, or 2
	// when one cannot join and is polled with `wait_any` instead), so a failure behind
	// a slow promise ends that run and the wait without waiting for the slow one. A run
	// that never waits costs nothing for watching. When the next promise is not
	// finished, block until any promise finishes and take it. The set reports each
	// finished promise once.
	var head = 0
	var tried = -1
	var mode = 0

	while head < count:
		if taken[head]:
			head += 1
			continue

		// Running an unstarted promise looks through the queue, so ask once per head: a
		// promise that was not there the first time never returns to it.
		fresh := head != tried
		tried = head

		var ran = 0
		if fresh:
			ran = msrt_promise_run_watched(pending[head].id, set.id, members, head)
		if run_interrupted(ran): return error(
			first_failure(set.id, pending, taken, head)
		)

		if not ran_nothing(ran) or pending[head].done():
			value := pending[head].wait()?
			slots[head] = ok(value)
			taken[head] = true
			head += 1
		else if not joined_partly(mode):
			mode = msrt_group_join(set.id, members, head)

			if not joined_partly(mode):
				at := msrt_group_next(set.id)

				if at >= 0 and not taken[at]:
					value := pending[at].wait()?
					slots[at] = ok(value)
					taken[at] = true
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
		slot := slots.pop()
		if slot != null:
			reversed.append(slot?)

	var results: List[T] = []

	for at in 0..count:
		value := reversed.pop()
		if value != null:
			results.append(value)

	return ok(results)

// Waits for the first promise to finish and returns its result; the others are
// cancelled and waited for. Errors are those of `wait`, and an empty list is an
// error.
export fn wait_first[T](promises: List[Promise[T]]) T!:
	var pending = promises
	if pending.is_empty(): return error(Error("promise: nothing to wait for"))

	var ids = pending.map(fn p: p.id)
	which := msrt_promise_wait_any(ids, -1)
	return pending[which].wait()

// Returns a promise whose work runs in the task that first waits on it, on that task's
// stack, with no task of its own. The work may wait itself. `work` receives the new
// promise's id and must finish with `complete(id, ...)`. This is for stream
// implementations. Dropping the promise before any wait discards the work unrun.
export fn deferred[U](work: fn(Int) Void) Promise[U]:
	id := msrt_promise_defer(fn id: work(id))
	return Promise[U](id: id)

// Wraps the runtime promise `id`, which a native operation completes (a stream read
// or flush), as a `Promise`.
export fn adopt[U](id: Int) Promise[U]:
	return Promise[U](id: id)
