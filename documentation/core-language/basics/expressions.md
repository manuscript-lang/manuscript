+++
title = "Expressions and operators"
weight = 5
+++

# Expressions and operators

Explicit grouping and pipe steps make the order of agent-written calculations easy to review; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::group a calculation\nPASS example.ms::group a calculation\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "group a calculation":
    let grouped = (1 + 2) * 3
    let product_first = 1 + 2 * 3
    try expect_equal(grouped, 9)
    try expect_equal(product_first, 7)
    try expect_equal(not product_first == 9, true)
```

```sh
ms test example.ms
```

```text
RUN example.ms::group a calculation
PASS example.ms::group a calculation
1 tests, 0 failed
```

- Operands evaluate left to right; `and` and `or` skip the unused right operand.
- Arithmetic requires matching numeric types; parenthesize the grouping a reviewer should see.

## Pipe flows

<!-- manuscript-example: {"mode":"test","stdout":"RUN port.ms::read a pipe from top to bottom\nPASS port.ms::read a pipe from top to bottom\n1 tests, 0 failed\n"} -->
```manuscript {filename="port.ms"}
import expect_equal from "@std/test/test.ms"

fn port_number(text: String) Int!:
    let number = text.trim()
        | .parse_int()
        | .ok_or(Error("expected digits"))
        | try
    return ok(number)

test "read a pipe from top to bottom":
    try expect_equal(try port_number(" 8080 "), 8080)
```

```sh
ms test port.ms
```

```text
RUN port.ms::read a pipe from top to bottom
PASS port.ms::read a pipe from top to bottom
1 tests, 0 failed
```

- `x | f` passes x as the first argument; `x | .method()` calls on x.
- `try` before a step handles that result; `| try` handles the value already flowing through.

<span id="precedence-and-grammar"></span><span id="operand-and-result-types"></span><span id="never-operands"></span><span id="evaluation"></span><span id="examples"></span>

Next: [operator checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/exprs.rs); [source grammar](grammar.md).
