+++
title = "Functions"
weight = 2
+++

# Functions

Function signatures expose what agent-written code reads and returns; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::review a function call\nPASS example.ms::review a function call\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn total(price: Int, quantity: Int) Int:
    return price * quantity

test "review a function call":
    try expect_equal(total(12, 3), 36)
```

```sh
ms test example.ms
```

```text
RUN example.ms::review a function call
PASS example.ms::review a function call
1 tests, 0 failed
```


Next: [Declarations and calls](declarations-and-calls.md) · [Function values and closures](function-values-and-closures.md) · [Native functions](native-functions.md).
