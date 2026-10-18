+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

Exports define what other files can use. Export the types that public functions name; keep helpers private.

This module exports a record and a function that uses it:

```manuscript

export type Item:
    price: Int
    quantity: Int

export fn total(items: List[Item]) -> Int:
    var result = 0
    for item in items:
        result += item.price * item.quantity
    return result
```

A caller imports `Item` to build values and `total` to use them. A public signature cannot expose a private type ([public type visibility](../types/records.md#public-data-surfaces)).

Functions that need files, network access, or other services can import a host accessor or take a service parameter. Parameters make dependencies visible and let tests substitute them. See services and [interfaces](../types/contracts.md).
