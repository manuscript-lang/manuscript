+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

Exports define what other files can use. Export the types that public functions name; keep helpers private.

Save this module as `pricing.ms`. It exports a type and the operation callers need:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
export type Item:
    price: Int
    quantity: Int

export fn total(items: List[Item]) Int:
    var result = 0
    for item in items:
        result += item.price * item.quantity
    return result
```

Save the caller as `main.ms` in the same directory:

```manuscript
import Item, total from "./pricing.ms"

export fn main() Int:
    print(total([Item(12, 3), Item(5, 2)]))
    return 0
```

Run `ms run main.ms`:

```text
46
```

The caller imports `Item` to build values and `total` to use them. A public signature cannot expose a private type ([public type visibility](../types/named-types.md#public-data-surfaces)).

Functions that need files, network access, or other services can import a host accessor or take a service parameter. Parameters make dependencies visible and let tests substitute them. See [interfaces](../types/contracts.md).
