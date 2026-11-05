+++
title = "Type checking and source contracts"
weight = 89
+++

# Type checking and source contracts

Assert named-argument mapping; save as `types.ms`.

<!-- manuscript-example: {"mode":"test","filename":"types.ms","stdout":"RUN types.ms::named arguments retain their meaning\nPASS types.ms::named arguments retain their meaning\n1 tests, 0 failed\n"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn total(price: Int, quantity: Int) Int:
    return price * quantity

test "named arguments retain their meaning":
    try expect_equal(total(quantity: 3, price: 12), 36)
```

```sh
ms test types.ms
```

```text
RUN types.ms::named arguments retain their meaning
PASS types.ms::named arguments retain their meaning
1 tests, 0 failed
```

- Labels determine parameter mapping, not evaluation order.
- Alpha: syntax and APIs may change.

<span id="required-checks"></span>

Next: [compatibility rules](../../../core-language/types/compatibility.md) and [typed HIR](typed-ir.md).
