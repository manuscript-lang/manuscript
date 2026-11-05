+++
title = "Parse text"
+++

# Parse text

Review how optional parsing results distinguish accepted text from invalid input. APIs may evolve during alpha.

## Check accepted boolean text

<!-- manuscript-example: {"mode":"test","filename":"parse-text.ms","stdout":"RUN parse-text.ms::parse-text\nPASS parse-text.ms::parse-text\n1 tests, 0 failed\n"} -->
```manuscript {filename="parse-text.ms"}
import parse_bool, parse_int_radix from "@std/text.ms"
import expect_equal from "@std/test/test.ms"

test "parse-text":
    try expect_equal(parse_bool("yes"), true)
    try expect_equal(parse_int_radix("-ff", 16), -255)
    try expect_equal(parse_bool("perhaps"), none)
```

```sh
ms test parse-text.ms
```

```text
RUN parse-text.ms::parse-text
PASS parse-text.ms::parse-text
1 tests, 0 failed
```

See the [API reference](../reference/text.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
