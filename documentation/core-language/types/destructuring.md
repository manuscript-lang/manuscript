+++
title = "Destructuring bindings"
weight = 6
+++

# Destructuring bindings

Destructuring shows exactly which parts an operation reads; Manuscript is in alpha and syntax/APIs may change.

<span id="positional-bindings"></span><span id="record-bindings"></span>

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::name the needed parts\nPASS example.ms::name the needed parts\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Customer:
    name: String
    city: String

test "name the needed parts":
    let customer = Customer("Ada", "London")
    let {name, city: destination} = customer
    let names = ["Ada", "Grace"]
    let [first, second] = names
    try expect_equal(name, first)
    try expect_equal(destination, "London")
    try expect_equal(second, "Grace")
```

```sh
ms test example.ms
```

```text
RUN example.ms::name the needed parts
PASS example.ms::name the needed parts
1 tests, 0 failed
```

- Patterns name parts of a value; `_` ignores a part. Only simple bindings take type annotations.
- Borrowed parts keep their owner available; storing a part independently moves it or requires a clone.

<span id="nested-patterns"></span>

Next: [type and ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [records](records.md).
