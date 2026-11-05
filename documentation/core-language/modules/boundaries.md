+++
title = "Module boundaries"
weight = 2
+++

# Module boundaries

A small public contract lets you review an agent’s caller without reading every helper; these alpha APIs may change.

Save this tested library as `pricing.ms`.

<!-- manuscript-example: {"mode":"test","filename":"pricing.ms","stdout":"RUN pricing.ms::total a basket\nPASS pricing.ms::total a basket\n1 tests, 0 failed\n"} -->
```manuscript {filename="pricing.ms"}
import expect_equal from "@std/test/test.ms"

export type Item:
    price: Int
    quantity: Int

export fn total(items: List[Item]) Int:
    var result = 0
    for item in items:
        result += item.price * item.quantity
    return result

test "total a basket":
    try expect_equal(total([Item(12, 3), Item(5, 2)]), 46)
```

```sh
ms test pricing.ms
```

```text
RUN pricing.ms::total a basket
PASS pricing.ms::total a basket
1 tests, 0 failed
```

- Export the types that public functions name; keep implementation helpers private.
- The function reads its argument and mutates only its local total.

Save the caller beside it as `main.ms`.

<!-- manuscript-example: {"mode":"run","filename":"main.ms","files":{"pricing.ms":"import expect_equal from \"@std/test/test.ms\"\n\nexport type Item:\n    price: Int\n    quantity: Int\n\nexport fn total(items: List[Item]) Int:\n    var result = 0\n    for item in items:\n        result += item.price * item.quantity\n    return result\n\ntest \"total a basket\":\n    try expect_equal(total([Item(12, 3), Item(5, 2)]), 46)\n"},"stdout":"46\n"} -->
```manuscript {filename="main.ms"}
import Item, total from "./pricing.ms"

export fn main() Int:
    print(total([Item(12, 3), Item(5, 2)]))
    return 0
```

```sh
ms run main.ms
```

```text
46
```

- The caller imports `Item` to construct values and `total` to calculate the result.
- Pass services as parameters when tests should substitute dependencies; import accessors when the function owns that choice.

Next: [public type visibility](../types/records.md#public-data-surfaces), [interfaces](../types/contracts.md), [imports and exports](declarations.md).
