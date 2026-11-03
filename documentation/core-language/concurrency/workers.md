+++
title = "Worker threads"
weight = 2
+++

# Worker threads

A `WorkerGroup[In, Out]` starts workers: functions that run on their own OS threads, in parallel with the caller, and talk to it over a two-way [channel](task-groups.md#channels). Import it from `@std/concurrency/workers.ms`. Use workers for CPU-bound work that tasks cannot spread across cores.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Channel from "@std/io/channels.ms"
import expect_equal, expect_ok from "@std/test/test.ms"
import WorkerGroup, worker_channel from "@std/concurrency/workers.ms"

fn serve(ch: Channel[Int, Int]) Unit!:
    while true:
        if let n = try ch.receive():
            try ch.send(n * n)
        else:
            return ok(unit)

    return ok(unit)

fn squares() Unit:
    let ch = worker_channel[Int, Int]()
    let _finished = serve(ch)

test "a worker answers over its channel":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(squares) | try expect_ok
    try expect_ok(worker.channel.send(12))
    try expect_equal(worker.channel.receive(), ok(144))
    worker.channel.close()
    try expect_ok(worker.wait())
```

## How workers run

- `spawn(entry)` starts `entry`, the name of a top-level `fn` that takes no arguments and returns `Unit`, and returns a `Worker[In, Out]!`. A closure, a local function or a captured value is a compile error: a worker shares no memory with its starter, so there is nothing to capture. Send what the worker needs through the channel.
- The worker takes its end of the channel with `worker_channel[Send, Receive]()`; the starter holds the other in `worker.channel`. A `WorkerGroup[In, Out]` sends `In` to its workers and receives `Out` from them.
- When the starter and its workers all wait on each other (the starter in `receive` or `result()`, a worker in `receive`, with no timer, descriptor wait or blocking call pending anywhere), the program stops with a deadlock fault on the main isolate instead of hanging, as it does within one isolate.
- Every worker has its own memory (2 GiB of address space, reserved lazily), scheduler and task tree. Tasks inside a worker run cooperatively, as in the main program.
- Every message is encoded as JSON and decoded on the other side, so message types are the ones `@std/data/json.ms` reads and writes. Transport uses ordinary `stringify`, not its opt-in `strict: true` mode; a typed channel does not guarantee a lossless JSON representation for every type. Use plain serializable data and check send/receive errors. `send` waits while the other side has 16 unread messages.
- `worker.wait()` closes the starter's end, waits for the worker to end, and returns `Unit!`. A worker that is reading ends when its input closes. `worker.cancel()` stops one that is not.
- Manuscript faults caught by the worker runtime are reported through `wait()` as an `Error` of kind `Failed`; `details["report"]` holds the fault's message and stack. Worker threads are not a process-crash isolation boundary. A cancelled worker gives an `Error` whose message is `worker: cancelled`.
- Leaving the scope of the group binding cancels workers that are still running, closes their channels and waits for them.
- At most 256 workers run at once; past that `spawn` returns an `Error` of kind `Unavailable`.

## What a worker may use

Use workers for CPU-bound work. A worker may use the network: HTTP `fetch` and connections run on the worker's own thread, so several workers download in parallel (four workers fetching from one server at once are covered by the conformance fixture `workers.ms`). To move large `Bytes` between a worker and its starter, use the raw pipe as a `Channel[Bytes, Bytes]` (`worker.bytes()` on the starter, `worker_bytes()` in the worker): each `send` is copied once into the other side's memory with no JSON. Read each message with the kind that was sent, because bytes and channel messages share one ordered queue. Standard input, the terminal and exit hooks fault with "only available on the main thread". Standard output works; a worker's writes go straight out, unbuffered, so they can appear before text the main thread has buffered.

Send plain serializable data. Messages reconstruct values through JSON; acceptance by the checker does not establish transfer suitability or preserve shared identity. Do not use worker messages to transfer live resources.

## Serving on several cores

`serve(address, handler, options)` runs on every core with no extra code. It binds a plain TCP listener and runs the accept loop as a promise; each accepted connection becomes a promise that the runtime places on the least busy thread, where it stays. HTTP/1.1, HTTP/2 and the TLS handshake of `options.tls` run on that thread, and `options.cores` limits the runtime to that many threads. The handler is built once and only read by every thread.

```manuscript
fn main() Int:
    let server = serve(":8080", buffered(app), HttpServerOptions(cores: 4)).get(none)
    let _ = server.wait()
    return 0
```

`close` stops accepting; connections drain within `grace`, then are cancelled, and `wait` returns.

## Cost

Worker throughput depends on available cores, job size and messaging costs. A message costs a JSON encode, a queue operation and a decode, so send work in chunks that take longer than the message does to move.
