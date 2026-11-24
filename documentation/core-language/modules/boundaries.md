+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

Exports define what other files can use. Export every type that an exported function names in its signature, and keep helpers private.

Save this module as `pricing.ms`. It exports a type and the operation callers need:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
export type Item {
    price Int
    quantity Int
}

export fn total(items List[Item]) Int {
    var result = 0
    for item in items {
        result += item.price * item.quantity
    }
    return result
}
```

Save the caller as `main.ms` in the same directory:

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import Item, total from "./pricing.ms"

fn main() Void {
    print(total([Item(12, 3), Item(5, 2)]))
}
```

Run `ms run main.ms`:

```text
46
```

The caller imports `Item` to build values and `total` to use them. A public signature cannot expose a private type ([public type visibility](../types/named-types.md#public-data-surfaces)).

A function that needs files, network access, or another service can import the operation it uses (such as `read_file` from `@std/os/fs.ms`) or take the service as a parameter. A parameter makes the dependency visible and lets tests substitute it. See [interfaces](../types/contracts.md).
