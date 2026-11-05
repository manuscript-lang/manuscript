+++
title = "Type compatibility and expected types"
weight = 10
+++

# Type compatibility and expected types

Expected types let reviewers see where inference ends and a checked contract begins; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::context determines the values\nPASS example.ms::context determines the values\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Input:
    names: List[String?]

fn double(value: Int) Int:
    return value * 2

test "context determines the values":
    let input = Input([none, "Ada"])
    let transform: fn(Int) Int = double
    let success: Int! = ok(transform(3))
    try expect_equal(try success, 6)
    try expect_equal(input.names.length(), 2)
```

```sh
ms test example.ms
```

```text
RUN example.ms::context determines the values
PASS example.ms::context determines the values
1 tests, 0 failed
```

- Records and enums have declared identities; equal field shapes do not make them interchangeable.
- Expected types guide literals, optional wrapping and typed `ok`/`error` constructors, without numeric widening or ambiguous name resolution.

<span id="exact-and-nominal-identity"></span><span id="propagating-context"></span><span id="validation-boundaries"></span>

Next: [type checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/checker.rs); [generics and bounds](generics.md).
