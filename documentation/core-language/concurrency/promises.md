+++
title = "Promises"
weight = 1
+++

# Promises

A `Promise[T]` represents an operation whose result is taken once with `wait()`. Calls such as `read_file(path)`, `write_file(path, ...)`, `fetch`, `connect`, `sleep`, `exec` and `Listener.accept` return one, and so does `promise(fn: ...)` for your own function.

Start with a normal function call when one step depends on the previous step. Use a promise when work can overlap something else: start the operation, keep its handle, do independent work, then wait where you need the result. Starting two operations before either wait allows overlap; starting and immediately waiting inside a loop handles one operation at a time.

## Start work and collect its value

Save as `totals.ms` and run `ms run totals.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Total: 42\n"} -->
```manuscript
import promise from "@std/concurrency/promise.ms"

fn total(values: List[Int]) Int:
    var result = 0
    for value in values:
        result += value
    return result

fn combined_total() Int!:
    let first = promise(fn: ok(total([10, 12])))
    let second = promise(fn: ok(total([7, 13])))
    let left = try first.wait()
    let right = try second.wait()
    return ok(left + right)

export fn main() Int:
    let outcome = combined_total()
    if let value = outcome:
        print("Total: {value}")
        return 0
    print(outcome.err().message)
    return 1
```

```text
Total: 42
```

The callback passed to `promise` returns `Int!`, so each handle is a `Promise[Int]`. Wrapping `total` in `ok` supplies that return type. Both callbacks can run before the first wait; their completion order does not change which value each handle returns. These tiny calculations illustrate the control flow, not a performance benefit—ordinary calls are sufficient for work this small.

`wait()` returns `Int!`, not just `Int`: even a callback that normally returns `ok` can be cancelled or fault. The helper propagates those errors, and `main` chooses the process exit status. There is no special asynchronous function declaration. A function that calls `wait()` may pause, including one called by another ordinary function.

## Bound an I/O operation

Save this complete program as `read-config.ms` and run `ms run read-config.ms` in a directory containing `config.json`:

<!-- manuscript-example: {"mode":"run","files":{"config.json":"{}"},"stdout":"2\n"} -->
```manuscript
import read_file from "@std/os/fs.ms"
import PromiseOptions from "@std/concurrency/promise.ms"

export fn main() Int:
    let pending = read_file("config.json").with(
        options: PromiseOptions(timeout: 5.seconds())
    )
    let outcome = pending.wait()
    if let contents = outcome:
        print(contents.length())
        return 0
    print(outcome.err().message)
    return 1
```

For a `config.json` containing exactly `{}` (two bytes), the program prints:

```text
2
```

`promise(fn: ...)` starts work eagerly. Each operation defines when its work begins. For incremental I/O and pipelines, see [Streams and pipes](streams.md).

## Waiting

`wait()` pauses the calling task until the work finishes, then moves the result out. Save that result if you need it again; a second wait does not repeat the operation or retrieve a cached copy. It reports `"EBADF"`. To do the work again, start another operation.

A successful wait produces `T`, wrapped in `ok`. A failed wait returns the operation's own error, or one of these:

| Error kind | Meaning |
| --- | --- |
| `"EIO"` | A fault happened inside the promise; the report is in `details["report"]`. |
| `"ECANCELED"` | The promise was cancelled before it finished. |
| `"EBADF"` | An earlier `wait` already took the result. |
| `"ETIMEDOUT"` | The promise's `timeout` option passed; the work was cancelled. |

`PromiseOptions(timeout: ...)` is given when a promise is made, with `promise(fn: ..., options: ...)`, or to a promise another call returned with `.with(options: ...)`, as in `read_file(path).with(options: PromiseOptions(timeout: 5.seconds()))`. The timeout counts from creation for `promise`, or from applying `.with` to an existing promise, and is enforced whether or not anyone waits; `wait` itself takes no timeout. A negative timeout is no time at all.

`done()` reports whether the work has finished, however it ended, and never waits.

`wait_all(promises)` returns a successful list of values in input order, or an error; it does not return a list of Results. It waits in input order, and the first error it encounters cancels and waits for the remaining work. `wait_first(promises)` returns the first completed operation's result, which may be an error, and cancels and waits for the others. Neither leaves losing work running in the background.

## Reading and changing shared values

A promise created with `promise(fn: ...)` reads what it captures, and nothing it captures can be changed from inside it. The exception is a resource (a pipe writer, a file) the promise captures at its last use: the promise owns it from then on, runs once, and may write to it if it is declared `var`, pass it on with `var`, or close it. A promise holding a borrow of a value keeps that value from changing until the promise is dropped or moved into `wait_all`. To change state from several promises, give it one owner and send it values through a [pipe](streams.md#pipes).

I/O operations copy their small arguments (paths, URLs, headers), so their promises borrow nothing.

Keep the distinction between reading captured data and returning new data. A callback can calculate and return a new total; it cannot increment a captured shared total. Wait for its result and update the owner's state afterward. For a sequence of updates while work runs, use a pipe and let its reader own the changing state. See [ownership and borrowing](../types/references.md) before moving resources into callbacks.

## Faults

A fault inside a promise ends only that promise, runs its cleanup, and `wait` reports it as `"EIO"`. This is a fault boundary, not a conversion of every failure in the program: `try` outside a promise still propagates only Result errors. The promise cannot mutate shared captured values. External operations such as file writes may already have happened, so handle partial effects at the application boundary. A fault in runtime code, or in code outside any promise, ends the program.

## Cancellation

Dropping an unfinished promise cancels it and waits for it to end, so work never outlives the values it uses. At the end of a scope, promises drop before the locals they read. An unused promise is a lint warning, because the work is cancelled the moment the value is dropped.

Cancellation is delivered at the next wait. `cancel()` asks the work to stop the same way and returns at once. A loop that never waits is not stopped by a timeout either; it ends at its next wait. Lint rule **MSL111** flags a `while true` loop that neither waits nor exits. Cleanup runs on cancellation as on any other exit.

`cancel_switch()` makes a `Cancel` that stops many promises at once. Give each promise `PromiseOptions(cancel: stop.signal())`; `stop.cancel()` then cancels all of them, now or later, and `wait` reports `"ECANCELED"`. A signal is a copy you can hand around, and `signal.cancelled()` tells a loop that never waits to stop. Dropping the `Cancel` cancels nothing. Applying another signal with `.with` replaces the previous one; `cancel: none` leaves it unchanged.

For several file reads, give each promise the same signal. Save as `cancel-reads.ms` and run `ms run cancel-reads.ms` beside the same two-byte `config.json`:

<!-- manuscript-example: {"mode":"run","files":{"config.json":"{}"}} -->
```manuscript
import cancel_switch, PromiseOptions from "@std/concurrency/promise.ms"
import read_file from "@std/os/fs.ms"

export fn main() Int:
    let paths = ["config.json"]
    let stop = cancel_switch()
    let options = PromiseOptions(timeout: 30.seconds(), cancel: stop.signal())
    let reads = paths.map(fn path: read_file(path).with(options: options.clone()))
    stop.cancel()
    for read in reads:
        let outcome = read.wait()
        if let contents = outcome:
            print("Completed before cancellation: {contents.length()} bytes")
        else:
            print(outcome.err().message)
    return 0
```

The output is either `Completed before cancellation: 2 bytes` or an error message such as `promise: cancelled`; the schedule is not deterministic. A read may finish before the switch fires. Inspect its result rather than assuming every operation was cancelled. Waiting observes the outcome and joins the work.

## Threads

The runtime keeps one thread per core. A new promise goes to the least busy thread and stays there; an idle thread takes promises that have not started yet. A program that never overlaps work runs on one thread. Calls the operating system cannot wait on, such as file system calls and name lookups, run on a small blocking pool while the calling promise waits.
