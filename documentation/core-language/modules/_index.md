+++
title = "Modules"
weight = 6
+++

# Modules

Module exports show the boundary a reviewer must understand; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::an exported operation\nPASS example.ms::an exported operation\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

export fn line_total(price: Int, quantity: Int) Int:
    return price * quantity

test "an exported operation":
    try expect_equal(line_total(12, 3), 36)
```

```sh
ms test example.ms
```

```text
RUN example.ms::an exported operation
PASS example.ms::an exported operation
1 tests, 0 failed
```


Next: [Imports and exports](declarations.md) · [Module boundaries](boundaries.md).
