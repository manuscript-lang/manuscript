import Closeable from "@std/core.ms"
import Duration from "@std/os/time.ms"
import (
    msrt_promise_new,
    msrt_promise_put,
    msrt_promise_take,
    msrt_promise_done,
    msrt_promise_start,
    msrt_promise_start_here,
    msrt_promise_defer,
    msrt_promise_wait,
    msrt_promise_limit,
    msrt_promise_cancel,
    msrt_promise_on_cancel,
    msrt_cancel_new,
    msrt_cancel_fire,
    msrt_cancel_fired,
    msrt_cancel_free,
    msrt_promise_wait_any,
    msrt_promise_fault_report,
    msrt_promise_drop
) from "@std/internal/promises.ms"

// Promises: work that has started, with its result arriving later.
//
// A call that can wait starts its work at once and returns a `Promise[T]`; `wait()` gives the result, and a task pauses
// only where the word `wait` appears. `promise(fn: ...)` runs your own function the same way, on a thread the runtime
// picks. Dropping a promise that has not finished cancels it and waits for it to end, so work you start never outlives
// the values it uses. A promise only reads what it captures: concurrent code never changes a shared value (to change
// shared state, give it one owner and send it values over a `pipe`).
//
// ```manuscript
// let config = read("config.json")  // Promise[Bytes], already running
// let words = promise(
//     fn: count_words(text), options: PromiseOptions(timeout: seconds(5))
// )  // may run on another thread, ends with Timeout after 5 s
// let bytes = try config.wait()
// let total = try words.wait()
// ```

// Work that has started; its result arrives later. Each `wait` takes the result once.
// Dropping an unfinished promise cancels it and waits for it to end; an unused promise is a warning.
export opaque type Promise[T]:
    // The runtime slot of this promise: a generation and an index, never reused while this id is live.
    id: Int

// What bounds a promise, fixed when it is made: `timeout` counts from construction and is enforced whether or not anyone
// waits; when it passes the work is cancelled and `wait` reports `Timeout`. A negative timeout is no time at all.
export type PromiseOptions:
    // How long the work may run, counted from construction; none means no limit.
    timeout: Duration? = none
    // When this signal's `Cancel` fires, the work is cancelled and `wait` reports `Cancelled`.
    cancel: Signal? = none

// One switch that cancels every promise made with its `signal()`. `cancel()` never waits; the work stops at its next wait
// and `wait` reports `Cancelled`. Dropping the switch does not cancel anything: promises made with its signals keep running.
export opaque type Cancel:
    // The runtime slot of this switch: a generation and an index.
    id: Int

// A new switch that has not fired.
export fn cancel_switch() Cancel:
    return Cancel(id: msrt_cancel_new())

// A copyable handle to a `Cancel`, passed in `PromiseOptions`. It reads as not cancelled once its `Cancel` is gone.
export opaque type Signal:
    // The slot of the `Cancel` it belongs to; a freed slot never matches.
    id: Int

impl Cancel:
    // A handle for `PromiseOptions(cancel: ...)`; make as many as you need.
    fn signal() Signal:
        return Signal(id: self.id)

    // Cancels every promise made with a signal of this switch, now and later. Safe to call again.
    fn cancel() Unit:
        msrt_cancel_fire(self.id)

impl Closeable for Cancel:
    // Frees the switch. Promises made with its signals keep running; they just cannot be cancelled by it any more.
    var fn close() Unit!:
        msrt_cancel_free(self.id)
        return ok(unit)

impl Signal:
    // Whether the switch has fired, for work that loops without waiting.
    fn cancelled() Bool:
        return msrt_cancel_fired(self.id)

// A limit in nanoseconds, or -1 for none. A negative duration is no time at all, not "none".
fn nanos(limit: Duration?) Int:
    if let own = limit:
        let total = own.to_nanoseconds()
        if total < 0:
            return 0

        return total

    return -1

// The error a `wait` that did not produce a result reports, from the runtime outcome code of the promise `id`.
fn outcome(id: Int, code: Int) Error:
    if code == 2:
        return Error("promise: timed out", kind: "ETIMEDOUT")
    if code == 3:
        return Error("promise: cancelled", kind: "EUNKNOWN")
    if code == 4:
        return Error("promise: the result was already taken", kind: "EBADF")

    let report = msrt_promise_fault_report(id)
    return Error(
        "promise: fault: " + report, kind: "EIO", details: {"report": report.clone()}
    )

// Applies `options` to the promise `id`.
fn limit(id: Int, options: PromiseOptions) Unit:
    if options.timeout.is_some():
        msrt_promise_limit(id, nanos(options.timeout))
    if let signal = options.cancel:
        msrt_promise_on_cancel(id, signal.id)

// Applies `options` to a promise in place, for an owner that keeps the promise (a server's accept loop). The timeout counts
// from now; `with` is the chaining form.
export fn set_options[T](target: Promise[T], options: PromiseOptions) Unit:
    limit(target.id, options)

// The result in the slot of `id`, moved out; `Closed` when it is gone.
fn taken_result[V](id: Int) V!:
    if let value = msrt_promise_take[V](id):
        return ok(value)

    return error(outcome(id, 4))

// The error in the slot of `id`, moved out.
fn taken_error(id: Int) Error:
    if let cause = msrt_promise_take[Error](id):
        return cause

    return outcome(id, 4)

impl Promise[T]:
    // Waits for the result and moves it out. Errors: the operation's own error; `Failed` (a fault inside, with its
// report in `details`); `Cancelled`; `Closed` (an earlier wait already took the result); `Timeout` once the promise's
    // `timeout` option has passed, which also cancelled the work.
    fn wait() T!:
        let code = msrt_promise_wait(self.id, -1)
        if code == 0:
            return taken_result[T](self.id)
        if code == 1:
            return error(taken_error(self.id))

        return error(outcome(self.id, code))

    // Applies `options` to a promise made elsewhere (`read`, `fetch`, `sleep`, `exec`) and returns it, so
    // `read(path).with(options: PromiseOptions(timeout: seconds(5))).wait()` bounds the read. The timeout counts from now.
    fn with(options: PromiseOptions) Promise[T]:
        limit(self.id, options)
        return self

    // Asks the work to stop at its next wait; `wait` then reports `Cancelled`. It returns at once, and dropping the promise
    // joins the work. A finished promise is unchanged.
    fn cancel() Unit:
        msrt_promise_cancel(self.id)

    // Whether the work has finished, however it ended. It never waits.
    fn done() Bool:
        return msrt_promise_done(self.id)

impl Closeable for Promise[T]:
    // Dropping a promise ends it: unfinished work is cancelled and waited for, and a result nobody took is dropped.
    var fn close() Unit!:
        msrt_promise_drop(self.id)
        return ok(unit)

// Stores how `entry` ended in the promise `id`.
export fn complete[U](id: Int, result: U!) Unit:
    match result:
        ok(value):
            msrt_promise_put(id, value, 0)
        error(cause):
            msrt_promise_put(id, cause, 1)

// Runs `entry` on a thread the runtime picks and returns its promise. The promise reads what `entry` captures, so the
// values it reads must outlive it and cannot change while it lives; nothing the entry captures can be changed from
// inside it. A fault inside ends only this promise: `wait` reports it as `Failed`.
export fn promise[U](
    entry: fn() U!,
    options: PromiseOptions = PromiseOptions()
) Promise[U]:
    let id = msrt_promise_new()
    msrt_promise_start(id, fn: complete(id, entry()))
    limit(id, options)
    return Promise[U](id: id)

// The values an operation copied for its promise, with the function that uses them. It is a resource, so the promise
// moves it in and owns it: the promise borrows nothing from the caller.
type Owned[A, U]:
    args: A
    work: fn(A) U!

impl Closeable for Owned[A, U]:
    var fn close() Unit!:
        return ok(unit)

impl Owned[A, U]:
    fn run() U!:
        return self.work(self.args)

// Runs `work(args)` as a promise that owns `args`, for operations that copy their small arguments (a path, a URL, headers)
// so the promise borrows nothing and may outlive the caller's values. `work` captures nothing. The operation only waits
// (on a file, a socket, a child process), so its task stays on the calling thread.
export fn owned_promise[A, U](args: A, work: fn(A) U!) Promise[U]:
    let id = msrt_promise_new()
    msrt_promise_start_here(
        id, owned_job[A, U](id, Owned[A, U](args: args, work: work))
    )
    return Promise[U](id: id)

// The entry of an owning promise: a closure that owns `owned`, since a closure that is returned owns its captures.
fn owned_job[A, U](id: Int, owned: Owned[A, U]) fn() Unit:
    return fn: complete(id, owned.run())

// Waits for every promise and returns the results in order. The first error ends the wait: the promises still running
// are cancelled and waited for before `wait_all` returns it.
export fn wait_all[T](promises: List[Promise[T]]) List[T]!:
    var pending = promises
    var results: List[T] = []
    for index in 0..pending.length():
        results.append(try pending[index].wait())
    return ok(results)

// Waits for the first promise to finish and returns its result; the others are cancelled and waited for. Errors as
// `wait` does; an empty list is an error.
export fn wait_first[T](promises: List[Promise[T]]) T!:
    var pending = promises
    if pending.is_empty():
        return error(Error("promise: nothing to wait for", kind: "EUNKNOWN"))

    var ids: List[Int] = []
    for p in pending:
        ids.append(p.id)

    let which = msrt_promise_wait_any(ids, -1)
    return pending[which].wait()

// A promise whose work runs in the task that first waits on it, on that task's stack, with no task of its own.
// The work may wait itself. `make` receives the new promise's id and returns the work; it ends with `complete(id, ...)`.
// For stream implementations: dropping the promise first discards the work unrun.
export fn deferred[U](work: fn(Int) Unit) Promise[U]:
    let id = msrt_promise_new()
    msrt_promise_defer(id, fn: work(id))
    return Promise[U](id: id)

// A promise over the runtime promise `id` that a native operation completes (a stream read or flush).
export fn adopt[U](id: Int) Promise[U]:
    return Promise[U](id: id)
