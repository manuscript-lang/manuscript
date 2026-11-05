+++
title = "Ownership glossary"
weight = 1
+++

# Ownership glossary

Track copies and mutation when reviewing an agent’s data flow; Manuscript is in alpha, and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::keep an independent copy\nPASS example.ms::keep an independent copy\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "keep an independent copy":
    var names = ["Sam"]
    let original = names.clone()
    names.append("Ada")
    try expect_equal(original, ["Sam"])
    try expect_equal(names, ["Sam", "Ada"])
```

```sh
ms test example.ms
```

```text
RUN example.ms::keep an independent copy
PASS example.ms::keep an independent copy
1 tests, 0 failed
```

- Owners drop values; moves transfer ownership, borrows lend access, and `clone()` copies independently. `var` permits mutation.

Next: [ownership](core-language/types/references.md), [resources](core-language/cleanup/_index.md), [enums](core-language/types/alternatives.md) and [promises](core-language/concurrency/promises.md).
