+++
title = "Semantic conformance tests"
weight = 104
+++

# Semantic conformance tests

Turn the expected result into an assertion; save as `decrement.ms`.

<!-- manuscript-example: {"mode":"test","filename":"decrement.ms","stdout":"RUN decrement.ms::checked decrement\nPASS decrement.ms::checked decrement\n1 tests, 0 failed\n"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

test "checked decrement":
    let value = 3
    try expect_equal(value - 1, 2)
```

```sh
ms test decrement.ms
```

```text
RUN decrement.ms::checked decrement
PASS decrement.ms::checked decrement
1 tests, 0 failed
```

- Place the smallest regression in `tests/e2e/testdata/`.
- Alpha: language rules may change.

<span id="required-coverage"></span>

Next: [regression fixtures](https://github.com/manuscript-lang/manuscript/tree/main/tests/e2e/testdata) and [conformance checks](../../development.md#conformance).
