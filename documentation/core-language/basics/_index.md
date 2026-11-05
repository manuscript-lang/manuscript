+++
title = "Basics"
weight = 1
+++

# Basics

Basic expressions let reviewers follow a value from input to result; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::read a small calculation\nPASS example.ms::read a small calculation\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "read a small calculation":
    let price = 12
    let quantity = 3
    let total = price * quantity
    try expect_equal(total, 36)
```

```sh
ms test example.ms
```

```text
RUN example.ms::read a small calculation
PASS example.ms::read a small calculation
1 tests, 0 failed
```


Next: [Source files](syntax.md) · [Variables and scope](bindings.md) · [Numbers and booleans](numbers-and-booleans.md) · [Strings and bytes](text-and-bytes.md) · [Expressions and operators](expressions.md) · [Source grammar](grammar.md).
