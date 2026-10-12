+++
title = "Foreign cancellation and resource acquisition"
weight = 85
+++

# Foreign cancellation and resource acquisition

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A blocking adapter must pass cancellation to its underlying operation and wait until outstanding work actually ends. Returning early while a foreign call keeps running would break Manuscript's join and cleanup guarantees.

Each blocking adapter defines how cancellation reaches the underlying operation and when cleanup completes. An uncancellable foreign call remains outstanding until it finishes; wrapping it in a goroutine and returning early violates joining guarantees. Host escalation is the final fallback. Adapters report acquired resources even when cancellation races with acquisition, so the runtime can close newly acquired undelivered resources.

## An acquisition race

Suppose a connection is acquired just as cancellation is accepted. The acquisition adapter must close it if delivery loses the race. Once delivered into `with`, cleanup registration has no intervening cancellation checkpoint. This contract applies to newly acquired resources, not arbitrary result references that may alias existing objects.

See [stable adapter contexts](../../concurrency/runtime.md#adapter-execution-contexts) and [result commitment](../../concurrency/runtime.md#completion-and-resource-acquisition).

[Previous: Foreign values and the trust boundary](value-conversion.md)
