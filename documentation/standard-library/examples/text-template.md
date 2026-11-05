+++
title = "Render a template"
+++

# Render a template

Review how typed values become rendered text. APIs may evolve during alpha.

## Render typed data

<!-- manuscript-example: {"mode":"test","filename":"render-template.ms","stdout":"RUN render-template.ms::render-template\nPASS render-template.ms::render-template\n1 tests, 0 failed\n"} -->
```manuscript {filename="render-template.ms"}
import compile, to_data from "@std/text/template.ms"

type User:
    name: String
import expect_equal from "@std/test/test.ms"

test "render-template":
    let page = try compile("Hello \{\{ name | title \}\}!")
    let data = try to_data(User(name: "ada"))
    try expect_equal(try page.render(data), "Hello Ada!")
```

```sh
ms test render-template.ms
```

```text
RUN render-template.ms::render-template
PASS render-template.ms::render-template
1 tests, 0 failed
```

See the [API reference](../reference/text/template.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
