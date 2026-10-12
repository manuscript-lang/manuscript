+++
title = "Byte streams"
weight = 11
+++

# Byte streams

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

Read requires positive max_bytes or returns IoError.InvalidInput. Under the declared return type, `ok(value: bytes)` wraps 1 through max_bytes bytes in a present Optional; `ok(value: none)` is EOF. Empty chunks never represent EOF. The bound limits each read, not total file size. Write waits until all bytes are accepted or an error occurs; empty writes succeed without I/O. An error may follow a partial external write and supplies no rollback. Internal buffering is bounded with backpressure.

Native wrappers serialize simultaneous reads/writes without holding a lifecycle lock during blocking I/O. Close marks admission closed, interrupts active I/O where supported, waits for admitted I/O to end, and releases the handle once. Later calls return IoError.Closed. Concurrent close callers wait for the same release/fault. A flag check followed by unsynchronized handle use is insufficient. Uncancellable I/O can delay release and requires host escalation; expected completion errors belong to read/write, and unexpected release failures are cleanup faults.

Contract values declaring these exact close operations are eligible for `with` under [Closeable](../core-language/cleanup/closeable.md); cleanup does not require concurrent sharing. Source fakes implement the selected stream contract and explicitly construct contract views when substituting for standard host roots or acquisitions; no native File constructor or contract inheritance is needed. Adapters honor [cancellation and undelivered acquisition](../contributing/compiler/adapters/cancellation.md).
