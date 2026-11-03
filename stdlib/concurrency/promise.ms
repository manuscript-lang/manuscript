import Closeable from "@std/core.ms"
import Duration from "@std/os/time.ms"
import (
    msrt_promise_new,
    msrt_promise_put,
    msrt_promise_take,
    msrt_promise_done,
    msrt_promise_start,
    msrt_promise_wait,
    msrt_promise_wait_any,
    msrt_promise_fault_report,
    msrt_promise_drop
) from "@std/internal/promises.ms"

# Promises: work that has started, with its result arriving later.
#
# A call that can wait starts its work at once and returns a `Promise[T]`; `wait()` gives the result, and a task pauses
# only where the word `wait` appears. `promise(fn: ...)` runs your own function the same way, on a thread the runtime
# picks. Dropping a promise that has not finished cancels it and waits for it to end, so work you start never outlives
# the values it uses. A promise only reads what it captures: concurrent code never changes a shared value (to change
# shared state, give it one owner and send it values over a `pipe`).
#
# ```manuscript
# let config = read("config.json")                    # Promise[Bytes], already running
# let words = promise(fn: count_words(text))          # may run on another thread
# let bytes = try config.wait()
# let total = try words.wait(timeout: seconds(5))
# ```

# Work that has started; its result arrives later. Each `wait` takes the result once.
# Dropping an unfinished promise cancels it and waits for it to end; an unused promise is a warning.
export opaque type Promise[T]:
    # The runtime slot of this promise: a generation and an index, never reused while this id is live.
    id: Int

# A limit in nanoseconds, or -1 for none.
fn nanos(limit: Duration?) Int:
    if let own = limit:
        return own.to_nanoseconds()

    return -1

# The error a `wait` that did not produce a result reports, from the runtime outcome code of the promise `id`.
fn outcome(id: Int, code: Int) Error:
    if code == 2:
        return Error("promise: timed out", kind: ErrorCategory.Timeout)
    if code == 3:
        return Error("promise: cancelled", kind: ErrorCategory.Other)
    if code == 4:
        return Error("promise: the result was already taken", kind: ErrorCategory.Closed)

    let report = msrt_promise_fault_report(id)
    return Error(
        "promise: fault: " + report, kind: ErrorCategory.Failed,
        details: {"report": report.clone()}
    )

# The result in the slot of `id`, moved out; `Closed` when it is gone.
fn taken_result[V](id: Int) V!:
    if let value = msrt_promise_take[V](id):
        return ok(value)

    return error(outcome(id, 4))

# The error in the slot of `id`, moved out.
fn taken_error(id: Int) Error:
    if let cause = msrt_promise_take[Error](id):
        return cause

    return outcome(id, 4)

impl Promise[T]:
    # Waits for the result and moves it out. Errors: the operation's own error; `Failed` (a fault inside, with its
    # report in `details`); `Cancelled`; `Closed` (an earlier wait already took the result); `Timeout` once `timeout`
    # passes, which also cancels the work. A negative timeout waits no time.
    fn wait(timeout: Duration? = none) T!:
        let code = msrt_promise_wait(self.id, nanos(timeout))
        if code == 0:
            return taken_result[T](self.id)
        if code == 1:
            return error(taken_error(self.id))

        return error(outcome(self.id, code))

    # Whether the work has finished, however it ended. It never waits.
    fn done() Bool:
        return msrt_promise_done(self.id)

impl Closeable for Promise[T]:
    # Dropping a promise ends it: unfinished work is cancelled and waited for, and a result nobody took is dropped.
    var fn close() Unit!:
        msrt_promise_drop(self.id)
        return ok(unit)

# Stores how `entry` ended in the promise `id`.
fn complete[U](id: Int, result: U!) Unit:
    match result:
        ok(value):
            msrt_promise_put(id, value, 0)
        error(cause):
            msrt_promise_put(id, cause, 1)

# Runs `entry` on a thread the runtime picks and returns its promise. The promise reads what `entry` captures, so the
# values it reads must outlive it and cannot change while it lives; nothing the entry captures can be changed from
# inside it. A fault inside ends only this promise: `wait` reports it as `Failed`.
export fn promise[U](entry: fn() U!) Promise[U]:
    let id = msrt_promise_new()
    msrt_promise_start(id, fn: complete(id, entry()))
    return Promise[U](id: id)

# Waits for every promise and returns the results in order. The first error ends the wait: the promises still running
# are cancelled and waited for before `wait_all` returns it.
export fn wait_all[T](promises: List[Promise[T]]) List[T]!:
    var pending = promises
    var results: List[T] = []
    for index in 0..pending.length():
        results.append(try pending[index].wait())

    return ok(results)

# Waits for the first promise to finish and returns its result; the others are cancelled and waited for. Errors as
# `wait` does; an empty list is an error.
export fn wait_first[T](promises: List[Promise[T]]) T!:
    var pending = promises
    if pending.is_empty():
        return error(Error("promise: nothing to wait for", kind: ErrorCategory.Other))

    var ids: List[Int] = []
    for p in pending:
        ids.append(p.id)

    let which = msrt_promise_wait_any(ids, -1)
    return pending[which].wait()
