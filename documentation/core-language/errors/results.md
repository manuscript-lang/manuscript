+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

Check both outcomes to review the value and cause an operation returns; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::quantity validation\nPASS example.ms::quantity validation\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn quantity(value: Int) Int!:
    if value <= 0:
        return error(Error("Quantity must be positive", kind: "EINVAL"))
    return ok(value)

test "quantity validation":
    try expect_equal(try quantity(3), 3)
    let cause = try expect_error(quantity(0))
    try expect_equal(cause.message, "Quantity must be positive")
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test example.ms
```

```text
RUN example.ms::quantity validation
PASS example.ms::quantity validation
1 tests, 0 failed
```

<a id="validate-a-value-and-show-the-outcome"></a>
<a id="shorthand-t-and-te"></a>
<a id="the-error-record"></a>
<a id="returning-a-domain-error"></a>
<a id="handling-the-result"></a>
<a id="checking-extracting-and-composing"></a>
<a id="converting-success-to-an-optional"></a>
<a id="discarding-a-result"></a>
<a id="converting-a-domain-error-to-error"></a>

- `T!` returns `T` or `Error`; `T!E` selects another cause type. Handle every Result.
- `Error` has a message, optional kind string and details map.

Next: [propagation](propagation.md), [domain enums](../types/alternatives.md) and [Result operations](../../standard-library/reference/core.ms.md#result).
