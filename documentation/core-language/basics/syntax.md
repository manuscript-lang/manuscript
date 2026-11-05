+++
title = "Source files"
weight = 1
+++

# Source files

A small source file lets a reviewer see the inputs, decision and checked result together; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::customer greeting\nPASS example.ms::customer greeting\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Customer:
    name: String
    active: Bool

fn welcome(customer: Customer) String:
    if customer.active:
        return "Welcome, {customer.name}!"
    return "Your account is inactive."

test "customer greeting":
    let customer = Customer("Ada", true)
    try expect_equal(welcome(customer), "Welcome, Ada!")
```

```sh
ms test example.ms
```

```text
RUN example.ms::customer greeting
PASS example.ms::customer greeting
1 tests, 0 failed
```

<span id="blocks-and-layout"></span><span id="module-boundaries"></span>

- Each block adds four spaces; its end is the dedent. Module-level executable work belongs in functions or tests.
- Imports name exact exports; records use `type`, choices use `enum`, and errors are handled explicitly.



Next: [source grammar](grammar.md); [variables and scope](bindings.md).
