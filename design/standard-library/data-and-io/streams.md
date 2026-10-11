+++
title = "Readers, writers, and streams"
weight = 40
+++

# Readers, writers, and streams

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The stream contracts have explicit cleanup operations and admit both native implementations and source fakes. The standard host exposes `ReadStream & Shareable`, `WriteStream & Shareable`, and `File & Shareable` views of its synchronized receivers. Bare stream contract types remain plain views under the ordinary interface rules.

```text
type ReadStream:
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn close() -> Unit

type WriteStream:
    fn write(data: Bytes) -> Result[Unit, IoError]
    fn close() -> Unit

type File:
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn close() -> Unit
```

Read requires positive max_bytes or returns IoError.InvalidInput. `ok(some(bytes))` contains 1 through max_bytes bytes; `ok(none)` is EOF. Empty chunks never represent EOF. The bound limits each read, not total file size. Write waits until all bytes are accepted or an error occurs; empty writes succeed without I/O. An error may follow a partial external write and supplies no rollback. Internal buffering is bounded with backpressure.

Native wrappers serialize simultaneous reads/writes without holding a lifecycle lock during blocking I/O. Close marks admission closed, interrupts active I/O where supported, waits for admitted I/O to end, and releases the handle once. Later calls return IoError.Closed. Concurrent close callers wait for the same release/fault. A flag check followed by unsynchronized handle use is insufficient. Uncancellable I/O can delay release and requires host escalation; expected completion errors belong to read/write, and unexpected release failures are cleanup faults.

Plain and shared contract values declaring these exact close operations are eligible for `with` under [Closeable](../../ownership-and-cleanup/cleanup/closeable.md); cleanup does not require concurrent sharing. Source fakes implement the selected stream contract and explicitly construct shared views when substituting for standard host roots or acquisitions; no native File constructor or contract inheritance is needed. Adapters honor [cancellation and undelivered acquisition](../../modules-and-capabilities/adapters/cancellation.md). Subprocess and network streaming still need acquisition, stream, and shutdown signatures.
