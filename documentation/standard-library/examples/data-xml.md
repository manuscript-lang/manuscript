+++
title = "Read XML elements"
+++

# Read XML elements

Review how parsed XML exposes element names and text. APIs may evolve during alpha.

## Inspect XML elements

<!-- manuscript-example: {"mode":"test","filename":"xml-elements.ms","stdout":"RUN xml-elements.ms::xml-elements\nPASS xml-elements.ms::xml-elements\n1 tests, 0 failed\n"} -->
```manuscript {filename="xml-elements.ms"}
import parse from "@std/data/xml.ms"
import expect_equal from "@std/test/test.ms"

test "xml-elements":
    let doc = try parse("<feed><item id=\"1\">Hi &amp; bye</item></feed>")
    let item = try doc.find("item").ok_or(Error("missing item"))
    try expect_equal(item.attribute("id"), "1")
    try expect_equal(item.text(), "Hi & bye")
```

```sh
ms test xml-elements.ms
```

```text
RUN xml-elements.ms::xml-elements
PASS xml-elements.ms::xml-elements
1 tests, 0 failed
```

See the [API reference](../reference/data/xml.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
