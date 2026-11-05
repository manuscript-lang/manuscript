+++
title = "Types"
weight = 3
+++

# Types

Data types make the shape of a change visible before execution; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::review an order\nPASS example.ms::review an order\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Order:
    quantity: Int
    note: String?

test "review an order":
    let order = Order(3)
    try expect_equal(order.quantity, 3)
    try expect_equal(order.note.is_none(), true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::review an order
PASS example.ms::review an order
1 tests, 0 failed
```


Next: [Records](records.md) · [Enums](alternatives.md) · [Collections](collections.md) · [Optional values](optionals.md) · [Mutation and references](references.md) · [Destructuring](destructuring.md) · [Interfaces](contracts.md) · [Equality and hashing](equality-and-hashing.md) · [Generics](generics.md) · [Type compatibility](compatibility.md).
