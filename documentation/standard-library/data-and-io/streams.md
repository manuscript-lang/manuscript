+++
title = "Readers, writers, and streams"
weight = 40
+++

# Readers, writers, and streams

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A stream reads or writes bytes over time. Its close operation releases the underlying resource. Native hosts and source fakes can both implement the contracts below.

The host supplies synchronized `ReadStream`, `WriteStream`, and `File` views. All stream contract values are safe to share; closing a stream still closes it through every alias.

```manuscript
interface ReadStream:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]
    fn close() -> Unit

interface WriteStream:
    fn write(data: Bytes) -> Result[Unit, IoError]
    fn close() -> Unit

interface File:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]
    fn close() -> Unit
```

Read requires positive max_bytes or returns IoError.InvalidInput. `ok(some(bytes))` contains 1 through max_bytes bytes; `ok(none)` is EOF. Empty chunks never represent EOF. The bound limits each read, not total file size. Write waits until all bytes are accepted or an error occurs; empty writes succeed without I/O. An error may follow a partial external write and supplies no rollback. Internal buffering is bounded with backpressure.

Native wrappers serialize simultaneous reads/writes without holding a lifecycle lock during blocking I/O. Close marks admission closed, interrupts active I/O where supported, waits for admitted I/O to end, and releases the handle once. Later calls return IoError.Closed. Concurrent close callers wait for the same release/fault. A flag check followed by unsynchronized handle use is insufficient. Uncancellable I/O can delay release and requires host escalation; expected completion errors belong to read/write, and unexpected release failures are cleanup faults.

Contract values declaring these exact close operations are eligible for `with` under [Closeable](../../ownership-and-cleanup/cleanup/closeable.md); cleanup does not require concurrent sharing. Source fakes implement the selected stream contract and explicitly construct contract views when substituting for standard host roots or acquisitions; no native File constructor or contract inheritance is needed. Adapters honor [cancellation and undelivered acquisition](../../modules-and-capabilities/adapters/cancellation.md). The bounded subprocess facility is exported by `@std/process.ms`. Import `commands() -> Commands` from `@std/process.ms` to obtain the host command service:

```manuscript
# Commands
fn run(program: String, arguments: List[String], input: Bytes,
       max_output_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[CommandOutput, CommandError]

type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes
```

`CommandError` has `InvalidInput`, `Unavailable`, `TimedOut`, `OutputLimit`, and `Failed(message: String)`. Empty/NUL program names, NUL arguments, negative bounds, and negative timeout return InvalidInput. The total stdout plus stderr bound is nonnegative. Nonzero ordinary exit is an `ok` output with that code. Timeout or output overflow stops and joins the process before returning its error; caller cancellation unwinds after joining. POSIX process groups include descendants in termination.

On platforms without process-group support the wrapper controls the direct process, with bounded pipe completion; descendant supervision needs a platform host contract. Interactive subprocess streams remain separate future contracts; [network sockets](../packages/network.md), [streaming HTTP](../packages/http.md) and [WebSockets](../packages/websocket.md) are implemented.
