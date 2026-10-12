+++
title = "Bounded queues"
weight = 41
+++

# Bounded queues

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use a queue to pass values from producers to consumers. `Queue[T]` has synchronized, bounded storage and requires shareable elements. Send and receive can wait and respond to cancellation. Closing the queue is explicit.

| Facility | Contract |
| --- | --- |
| `Queue[T]` | Shareable elements; synchronized bounded queue; cancellable send/receive; explicit close |

## Using the contract

Sending and receiving must respond to cancellation. Explicit close is part of the contract, so shutdown needs a deliberate end to admission and communication. A queue is a library facility and does not introduce another concurrency syntax.

## API

`Queue[T: Shareable](capacity: Int)` creates synchronized storage with positive capacity. The queue is opaque, shareable, and neither equal nor hashable. A nonpositive capacity is a programming fault.

```manuscript
fn send(value: T) -> Result[Unit, QueueError]
fn receive() -> Optional[T]
fn close() -> Unit
```

Import `Queue` and `QueueError` from `@std/queues.ms`; `QueueError` has the nullary case `Closed`. Send waits for space, receive waits for a value, and both respond to caller cancellation. Close atomically stops send admission and wakes all waiters. Already buffered values drain in FIFO order; once drained, receive returns `none`, including repeated receives. Blocked and later senders return `error(cause: QueueError.Closed)`. Close is idempotent and is eligible for `with`. A committed send or receive may precede cancellation; cancellation does not roll back queue effects.

See [shareable collection elements](../../core-language/types/collections.md) and [cooperative cancellation](../../concurrency/cancellation.md#propagation-and-checkpoints).

[Previous: Readers, writers, and streams](../data-and-io/streams.md) · [Next: Synchronized state, pools, and leases](../data-and-io/synchronized-state.md)
