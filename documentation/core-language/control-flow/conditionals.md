+++
title = "Conditionals"
weight = 1
+++

# Conditionals

Choose a greeting for a present or missing name. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::present and missing names\nPASS example.ms::present and missing names\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn greeting(name: String?) String:
    if let value = name:
        return "Hello, {value}!"
    return "Hello!"

test "present and missing names":
    try expect_equal(greeting("Sam"), "Hello, Sam!")
    try expect_equal(greeting(none), "Hello!")
    let count = 0
    let label = if count == 0: "empty" else: "ready"
    try expect_equal(label, "empty")
```

```sh
ms test example.ms
```

```text
RUN example.ms::present and missing names
PASS example.ms::present and missing names
1 tests, 0 failed
```

<a id="if-as-an-expression"></a>
<a id="unwrapping-an-optional-or-result"></a>
<a id="validating-inputs"></a>
<a id="bindings-after-a-branch"></a>

- `if let` handles a present optional or successful Result; zero, false and empty strings still count as present.
- `if` expressions need compatible branches. Use `match` when you need to inspect a Result’s error.

Next: [Results](../errors/results.md) and [scope rules](../basics/bindings.md#scope-and-shadowing).
