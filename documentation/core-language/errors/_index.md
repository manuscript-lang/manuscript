+++
title = "Error handling"
weight = 5
+++

# Error handling

Reject invalid quantities to review which failures callers can handle; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::valid and invalid quantities\nPASS example.ms::valid and invalid quantities\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn quantity(value: Int) Int!:
    if value <= 0:
        return error(Error("Quantity must be positive", kind: "EINVAL"))
    return ok(value)

test "valid and invalid quantities":
    try expect_equal(try quantity(3), 3)
    let cause = try expect_error(quantity(0))
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test example.ms
```

```text
RUN example.ms::valid and invalid quantities
PASS example.ms::valid and invalid quantities
1 tests, 0 failed
```

- Expected failures are values: return a cause, then handle it or forward it with `try`.

Next: [Results](results.md), [propagation](propagation.md) and [programming faults](faults.md).
