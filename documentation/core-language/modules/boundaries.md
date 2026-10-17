+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

A module's exports define what other files can use. Export the types named by public functions, and keep private helpers inside their defining module.

This module exports a record and a function that uses it:

```manuscript

export type Item:
    price: Int
    quantity: Int

export fn total(items: List[Item]) -> Int:
    var result = 0
    for item in items:
        result = result + item.price * item.quantity
    return result
```

A caller imports `Item` to construct values and `total` to calculate their total. It does not need to know how the function is implemented. A public signature cannot expose a private type; see [public type visibility](../types/records.md#public-data-surfaces).

Functions that need files, network access, or other services can import a host accessor or receive a service as an ordinary parameter. Parameters make dependencies visible and let tests supply another implementation. See services for the rules and [interfaces](../types/contracts.md) for operation contracts.
