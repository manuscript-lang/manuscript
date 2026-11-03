+++
title = "Promises"
weight = 1
+++

# Promises

A `Promise[T]` is work that has started; its result arrives later. Calls such as `read(path)`, `write(path, ...)`, `fetch`, `connect`, `sleep`, `exec` and `Listener.accept` return one, and so does `promise(fn: ...)` for your own function.

```manuscript
fn summarize(urls: List[String]) Summary!:
    let config = read("config.json")                 // Promise[Bytes], already running
    let pages = urls.map(fn u: fetch(u))             // all in flight together
    let stats = promise(fn: count_words(urls))       // may run on another core

    let settings = try config.wait()
    let bodies = try wait_all(pages)
    let words = try stats.wait(timeout: seconds(5))
    let mirror = try wait_first([fetch(a), fetch(b)])
    return ok(Summary(settings, bodies, words, mirror))
```

## Waiting

`wait()` pauses the calling task until the work finishes, then moves the result out. It returns the operation's own error, or one of these:

| Error kind | Meaning |
| --- | --- |
| `Failed` | A fault happened inside the promise; the report is in `details`. |
| `Cancelled` | The promise was cancelled before it finished. |
| `Closed` | An earlier `wait` already took the result. |
| `Timeout` | `timeout` passed; the work is cancelled. |

`done()` reports whether the work has finished, however it ended, and never waits.

`wait_all(promises)` returns every result in order; the first error cancels the rest. `wait_first(promises)` returns the first result and cancels the others.

## Cancellation

Dropping an unfinished promise cancels it and waits for it to end, so work never outlives the values it uses. At the end of a scope, promises drop before the locals they read. An unused promise is a lint warning, because the work is cancelled the moment the value is dropped.

Cancellation is delivered at the next wait. A loop that never waits is not stopped by a timeout; `wait(timeout: ...)` on a CPU-bound promise takes effect at its next wait. Lint rule **MSL111** flags a `while true` loop that neither waits nor exits. Cleanup runs on cancellation as on any other exit.

## Reading and changing shared values

A promise created with `promise(fn: ...)` reads what it captures, and nothing it captures can be changed from inside it. The exception is a resource (a pipe writer, a file) the promise captures at its last use: the promise owns it from then on, runs once, and may write to it if it is declared `var`, pass it on with `var`, or close it. A promise holding a borrow of a value keeps that value from changing until the promise is dropped or moved into `wait_all`. To change state from several promises, give it one owner and send it values:

```manuscript
var updates = pipe[Update](capacity: 64)
var input = updates.reader()
var out = updates.writer()
let owner = promise(fn: apply_all(var input, state))
let worker = promise(fn: produce(var out))
```

I/O operations copy their small arguments (paths, URLs, headers), so their promises borrow nothing.

## Faults

A fault inside a promise ends only that promise, and `wait` reports it as `Failed`. Because a promise cannot write outside state, nothing is left half-written. A fault in runtime code, or in code outside any promise, ends the program.

## Threads

The runtime keeps one thread per core. A new promise goes to the least busy thread and stays there; an idle thread takes promises that have not started yet. A program that never overlaps work runs on one thread. Calls the operating system cannot wait on, such as file system calls and name lookups, run on a small blocking pool while the calling promise waits.
