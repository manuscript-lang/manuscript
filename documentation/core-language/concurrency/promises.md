+++
title = "Promises"
weight = 1
+++

# Promises

A `Promise[T]` represents an operation whose result is taken once with `wait()`. Calls such as `read_file(path)`, `write_file(path, ...)`, `fetch`, `connect`, `sleep`, `exec` and `Listener.accept` return one, and so does `promise(fn: ...)` for your own function.

Save this complete program as `read-config.ms` and run `ms run read-config.ms` in a directory containing `config.json`:

<!-- manuscript-example: {"mode":"run","files":{"config.json":"{}"},"stdout":"2\n"} -->
```manuscript
import read_file from "@std/os/fs.ms"
import PromiseOptions from "@std/concurrency/promise.ms"

fn main() Unit!:
    pending := read_file("config.json").with(
        options: PromiseOptions(timeout: 5.seconds())
    )
    contents := pending.wait()?
    print(contents.length())
```

For a `config.json` containing exactly `{}` (two bytes), the program prints:

```text
2
```

`promise(fn: ...)` starts work eagerly. Each operation defines when its work begins. For incremental I/O and pipelines, see [Streams and pipes](streams.md).

## Waiting

`wait()` pauses the calling task until the work finishes, then moves the result out. It returns the operation's own error, or one of these:

| Error kind | Meaning |
| --- | --- |
| `"EIO"` | A fault happened inside the promise; the report is in `details["report"]`. |
| `"ECANCELED"` | The promise was cancelled before it finished. |
| `"EBADF"` | An earlier `wait` already took the result. |
| `"ETIMEDOUT"` | The promise's `timeout` option passed; the work was cancelled. |

`PromiseOptions(timeout: ...)` is given when a promise is made, with `promise(fn: ..., options: ...)`, or to a promise another call returned with `.with(options: ...)`, as in `read_file(path).with(options: PromiseOptions(timeout: 5.seconds()))`. The timeout counts from creation for `promise`, or from applying `.with` to an existing promise, and is enforced whether or not anyone waits; `wait` itself takes no timeout. A negative timeout is no time at all.

`PromiseOptions(placement: ...)` picks the thread: `Placement.Any` (the default) lets the runtime choose, `Placement.Spread` starts the work on the least loaded thread at once (one serving worker per core), and `Placement.Here` runs it as a task on the calling thread, for work that uses a network, connection or socket bound to that thread and only waits. The entry follows the ordinary capture rules: a promise that is returned owns what its closure captures, and one that is stored or stays in the function reads its captures in place, so the captured values must outlive it (a value made inside a loop body does not; start the promise in a helper that returns it).

`cancel_switch()` makes a `Cancel` that stops many promises at once. Give each promise `PromiseOptions(cancel: stop.signal())`; `stop.cancel()` then cancels all of them, now or later, and `wait` reports `"ECANCELED"`. A signal is a copy you can hand around, and `signal.cancelled()` tells a loop that never waits to stop. Dropping the `Cancel` cancels nothing. Applying another signal with `.with` replaces the previous one; `cancel: none` leaves it unchanged.

For several file reads, give each promise the same signal (this fragment assumes `paths` is a `List[String]` and imports `cancel_switch`):

```manuscript
stop := cancel_switch()
options := PromiseOptions(timeout: 30.seconds(), cancel: stop.signal())
reads := paths.map(fn path: read_file(path).with(options: options.clone()))
stop.cancel()
```

`done()` reports whether the work has finished, however it ended, and never waits.

`wait_all(promises)` returns every result in order; the first error cancels the rest. `wait_first(promises)` returns the first result and cancels the others.

## Cancellation

Dropping an unfinished promise cancels it and waits for it to end, so work never outlives the values it uses. At the end of a scope, promises drop before the locals they read. An unused promise is a lint warning, because the work is cancelled the moment the value is dropped.

Cancellation is delivered at the next wait. `cancel()` asks the work to stop the same way and returns at once. A loop that never waits is not stopped by a timeout either; it ends at its next wait. Lint rule **MSL111** flags a `while true` loop that neither waits nor exits. Cleanup runs on cancellation as on any other exit.

## Reading and changing shared values

A promise created with `promise(fn: ...)` reads what it captures, and nothing it captures can be changed from inside it. The exception is a resource (a pipe writer, a file) the promise captures at its last use: the promise owns it from then on, runs once, and may write to it if it is declared `var`, pass it on with `var`, or close it. A promise holding a borrow of a value keeps that value from changing until the promise is dropped or moved into `wait_all`. To change state from several promises, give it one owner and send it values through a [pipe](streams.md#pipes).

A promise a function returns outlives the call, so it owns what it captures instead of borrowing it: the function moves the captured parameters and locals into the promise, and a caller that wants to keep a value passes `.clone()`. A promise returned by name, or kept in a record, still borrows what it captured and cannot outlive those values.

I/O operations copy their small arguments (paths, URLs, headers), so their promises borrow nothing.

## Faults

A fault inside a promise ends only that promise, and `wait` reports it as `"EIO"`. The promise cannot mutate shared captured values. External operations such as file writes may already have happened, so handle partial effects at the application boundary. A fault in runtime code, or in code outside any promise, ends the program.

## Threads

The runtime keeps one thread per core. A new promise goes to the least busy thread and stays there; an idle thread takes promises that have not started yet. A program that never overlaps work runs on one thread. Calls the operating system cannot wait on, such as file system calls and name lookups, run on a small blocking pool while the calling promise waits.
