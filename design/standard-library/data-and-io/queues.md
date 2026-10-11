+++
title = "Bounded queues"
weight = 41
+++

# Bounded queues

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A queue connects producers and consumers through synchronized, bounded storage. It carries shareable values.

| Facility | Contract |
| --- | --- |
| `Queue[T]` | Shareable elements; synchronized bounded queue; cancellable send/receive; explicit close |

## Using the contract

Sending and receiving must respond to cancellation. Explicit close is part of the contract, so shutdown needs a deliberate end to admission and communication. A queue is a library facility and does not introduce another concurrency syntax.

The API still needs constructor/capacity rules, send and receive signatures, result alternatives, and close behavior. Specify whether close drains buffered values, how receivers observe EOF, and what happens to blocked senders and receivers.

See [shareable collection elements](../../core-language/types/collections.md) and [cooperative cancellation](../../concurrency/cancellation.md#propagation-and-checkpoints).

[Previous: Readers, writers, and streams](../data-and-io/streams.md) · [Next: Synchronized state, pools, and leases](../data-and-io/synchronized-state.md)
