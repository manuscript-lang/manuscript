+++
title = "Worker threads"
weight = 2
+++

# Worker threads

A `WorkerGroup[In, Out]` starts workers: functions that run on their own OS threads, in parallel with the caller, and talk to it over a two-way [channel](task-groups.md#channels). Import it from `@std/workers.ms`. Use workers for CPU-bound work that tasks cannot spread across cores.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {Channel, ChannelError} from "@std/channels.ms"
import {expect_equal, expect_ok} from "@std/test.ms"
import {WorkerGroup, worker_channel} from "@std/workers.ms"

fn serve(var ch: Channel[Int, Int]) Result[Unit, ChannelError]:
    while true:
        if let n = try ch.receive():
            try ch.send(n * n)
        else:
            return ok(unit)

    return ok(unit)

fn squares() Unit:
    var ch = worker_channel[Int, Int]()
    let _finished = serve(var ch)

test "a worker answers over its channel":
    with let group = WorkerGroup[Int, Int]():
        var worker = group.spawn(squares) | try expect_ok
        try expect_ok(worker.channel.send(12))
        try expect_equal(worker.channel.receive(), ok(some(144)))
        worker.channel.close()
        try expect_ok(worker.wait())
```

## How workers run

- `spawn(entry)` starts `entry`, the name of a top-level `fn` that takes no arguments and returns `Unit`, and returns a `Result[Worker[In, Out], WorkerError]`. A closure, a local function or a captured value is a compile error: a worker shares no memory with its starter, so there is nothing to capture. Send what the worker needs through the channel.
- The worker takes its end of the channel with `worker_channel[Send, Receive]()`; the starter holds the other in `worker.channel`. A `WorkerGroup[In, Out]` sends `In` to its workers and receives `Out` from them.
- When the starter and its workers all wait on each other (the starter in `receive` or `result()`, a worker in `receive`, with no timer, descriptor wait or blocking call pending anywhere), the program stops with a deadlock fault on the main isolate instead of hanging, as it does within one isolate.
- Every worker has its own memory (2 GiB of address space, reserved lazily), scheduler and task tree. Tasks inside a worker run cooperatively, as in the main program.
- Every message is encoded as JSON and decoded on the other side, so message types are the ones `@std/json.ms` reads and writes. Transport uses ordinary `stringify`, not its opt-in `strict: true` mode; a typed channel does not guarantee a lossless JSON representation for every type. Use plain serializable data and check send/receive errors. `send` waits while the other side has 16 unread messages.
- `worker.wait()` closes the starter's end, waits for the worker to end, and returns `Result[Unit, WorkerError]`. A worker that is reading ends when its input closes. `worker.cancel()` stops one that is not.
- Manuscript faults caught by the worker runtime are reported through `wait()` as `WorkerError.Faulted(report)`, with the fault's message and stack. Worker threads are not a process-crash isolation boundary. A cancelled worker gives `WorkerError.Cancelled`.
- Leaving the `with` block cancels workers that are still running, closes their channels and waits for them.
- At most 256 workers run at once; past that `spawn` returns `WorkerError.NotStarted`.

## What a worker may use

Use workers for CPU-bound work. A worker may use the network: HTTP `fetch` and connections run on the worker's own thread, so several workers download in parallel (four workers fetching from one server at once are covered by the conformance fixture `workers.ms`). To move large `Bytes` between a worker and its starter, use the raw pipe as a `Channel[Bytes, Bytes]` (`worker.bytes()` on the starter, `worker_bytes()` in the worker): each `send` is copied once into the other side's memory with no JSON. Read each message with the kind that was sent, because bytes and channel messages share one ordered queue. Standard input, the terminal and exit hooks fault with "only available on the main thread". Standard output works; a worker's writes go straight out, unbuffered, so they can appear before text the main thread has buffered.

Send plain serializable data. Messages reconstruct values through JSON; acceptance by the checker does not establish transfer suitability or preserve shared identity. Do not use worker messages to transfer live resources.

## Serving on several cores

Each worker can run its own HTTP server. Pass `HttpServerOptions(shared: true)` and every server of the process that serves the same address text accepts from one listening socket, so connections spread over the workers' threads. The first server binds the port and it closes with the last. This works the same on Linux, macOS and Windows.

```manuscript
fn serve_loop() Unit:
    var ch = worker_channel[Int, Int]()
    let options = HttpServerOptions(shared: true)
    if let acquired = network().serve(address: "127.0.0.1:8080", handler: buffered(app), options: options):
        with let server = acquired:
            let _stopped = server.wait()
```

Start one worker per core with `group.spawn(serve_loop)`. Measured with a CPU-bound handler on two server cores: one thread 23k requests per second, two workers 45k. A handler runs on the worker that accepted the connection and shares no memory with the other workers.

## Cost

Worker throughput depends on available cores, job size and messaging costs. A message costs a JSON encode, a queue operation and a decode, so send work in chunks that take longer than the message does to move.
