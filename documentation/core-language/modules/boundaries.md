+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

Exports define what other files can use. Export the types that public functions name; keep helpers private.

Save this module as `pricing.ms`. It exports a record and the operation callers need:

<!-- manuscript-example: {"mode":"check","filename":"pricing.ms","stdout":"Checked pricing.ms\n"} -->
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

Running `ms check pricing.ms` checks this module without starting it:

```text
Checked pricing.ms
```

Save the caller as `main.ms` in the same directory:

<!-- manuscript-example: {"mode":"run","build_files":{"pricing.ms":"export type Item:\n    price: Int\n    quantity: Int\n\nexport fn total(items: List[Item]) Int:\n    var result = 0\n    for item in items:\n        result += item.price * item.quantity\n    return result\n"},"stdout":"46\n","filename":"main.ms"} -->
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

The result is `12 * 3 + 5 * 2`: the caller supplies the order, and the pricing module owns the calculation. You can change the calculation in one file without duplicating it in every caller. The file boundary also gives tests a small operation to exercise without running the application's `main`.

The caller imports `Item` to build values and `total` to use them. A public signature cannot expose a private type ([public type visibility](../types/records.md#public-data-surfaces)).

Keep decisions that change together in the same module. For example, adding a discount rule to pricing should not require the caller to know how the calculation is implemented. A private helper can support `total` without becoming another import callers depend on. Exports are a promise about what other modules can name, not a requirement to export every declaration.

Functions that need files, network access, or other services can import a host accessor or take a service parameter. Parameters make dependencies visible and let tests substitute them. See [interfaces](../types/contracts.md).
