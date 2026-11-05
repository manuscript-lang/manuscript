+++
title = "Language reference"
weight = 2
+++

# Language reference

Check success and failure to review an operation’s contract; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::visible success and failure\nPASS example.ms::visible success and failure\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn doubled(value: Int) Int!:
    if value < 0:
        return error(Error("Expected a nonnegative value", kind: "EINVAL"))
    return ok(value * 2)

test "visible success and failure":
    try expect_equal(try doubled(4), 8)
    let cause = try expect_error(doubled(-1))
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test example.ms
```

```text
RUN example.ms::visible success and failure
PASS example.ms::visible success and failure
1 tests, 0 failed
```

- `try` makes the successful path linear while forwarding the original error.
- Check data types, ownership and handled outcomes when reviewing generated code.

Start with the [tour](../learn/tour.md), then [types](types/_index.md), [resources](cleanup/_index.md) and [concurrency](concurrency/_index.md).
