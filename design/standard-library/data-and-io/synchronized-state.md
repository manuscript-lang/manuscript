+++
title = "Synchronized state, pools, and leases"
weight = 42
+++

# Synchronized state, pools, and leases

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Shared application state and pools are synchronized services. A pool lease is an ordinary resource object registered with `with` and returned to the pool by `close()`.

Pool references can be shared by requests and background work. A job acquires its own lease under its own scope. Retaining a lease reference does not prolong its lease lifetime.

Access and closure must be coordinated: close waits for or cancels outstanding operations before allowing reuse, and stale aliases report closed state rather than using a connection assigned to another caller. Supported simultaneous use is explicit in the adapter/service contract.

The API still needs state operations, pool construction and capacity, lease acquisition/results, cancellation while waiting, and supported concurrent use. See [sharing](../../ownership-and-cleanup/values/sharing.md), [release](../../ownership-and-cleanup/cleanup/resource-release.md), and [background resources](../tasks/background.md).
