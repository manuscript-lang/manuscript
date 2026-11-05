+++
title = "Variables and scope"
weight = 2
+++

# Variables and scope

Bindings make mutation visible when reviewing a change; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::remaining stock\nPASS example.ms::remaining stock\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "remaining stock":
    let initial = 3
    var remaining = initial
    remaining -= 1
    try expect_equal(initial, 3)
    try expect_equal(remaining, 2)
```

```sh
ms test example.ms
```

```text
RUN example.ms::remaining stock
PASS example.ms::remaining stock
1 tests, 0 failed
```

<span id="local-type-inference"></span><span id="reassignment-and-references"></span>

- `let` prevents mutation; `var` makes intended changes explicit. Types stay fixed after initialization.
<span id="scope-and-shadowing"></span>

- Locals cannot shadow locals or parameters unless the new name starts with `_`; unused names also begin with `_`.

## Grouping bindings

<!-- manuscript-example: {"mode":"test","stdout":"RUN settings.ms::grouped settings\nPASS settings.ms::grouped settings\n1 tests, 0 failed\n"} -->
```manuscript {filename="settings.ms"}
import expect_equal from "@std/test/test.ms"

test "grouped settings":
    let (
        name = "Ada"
        attempts = 3
    )
    try expect_equal(name, "Ada")
    try expect_equal(attempts, 3)
```

```sh
ms test settings.ms
```

```text
RUN settings.ms::grouped settings
PASS settings.ms::grouped settings
1 tests, 0 failed
```

- Group entries use lines, not commas; later entries can use earlier ones.
- A binding group cannot appear inside an inline body.

<span id="destructuring"></span>

Next: [ownership rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/OWNERSHIP.md); [mutation and references](../types/references.md).
