+++
title = "Control flow"
weight = 4
+++

# Control flow

Trace the enabled branch and changing total to review which prices contribute; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::total enabled prices\nPASS example.ms::total enabled prices\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "total enabled prices":
    let enabled = true
    var total = 0
    if enabled:
        for price in [12, 8]:
            total += price
    try expect_equal(total, 20)
```

```sh
ms test example.ms
```

```text
RUN example.ms::total enabled prices
PASS example.ms::total enabled prices
1 tests, 0 failed
```

- `if` chooses work; `for` visits each price. Only the `var total` binding changes.

Next: [conditionals](conditionals.md), [loops](loops.md) and [pattern matching](pattern-matching.md).
