+++
title = "Error propagation with try"
weight = 2
+++

# Error propagation with try

Follow `try` to review where the original error returns; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::forward the original error\nPASS example.ms::forward the original error\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn quantity(value: Int) Int!:
    if value <= 0:
        return error(Error("Quantity must be positive", kind: "EINVAL"))
    return ok(value)

fn label(value: Int) String!:
    let count = try quantity(value)
    return ok("Quantity: {count}")

test "forward the original error":
    try expect_equal(try label(3), "Quantity: 3")
    let cause = try expect_error(label(0))
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test example.ms
```

```text
RUN example.ms::forward the original error
PASS example.ms::forward the original error
1 tests, 0 failed
```

<a id="success-and-failure-paths"></a>
<a id="try-in-a-pipe-flow"></a>
<a id="error-compatibility"></a>
<a id="cleanup-and-cancellation"></a>

- `try` forwards the cause from its function or closure; the caller must accept the same error type.
- It preserves payload borrows and cleans up early exits; it cannot catch faults or cancellation.

Next: [Result operations](../../standard-library/reference/core.ms.md#result), [borrowing](../types/references.md) and [cleanup](../cleanup/_index.md).
