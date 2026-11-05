+++
title = "Optional values"
weight = 4
+++

# Optional values

An optional makes missing input visible without hiding the fallback; Manuscript is in alpha and syntax/APIs may change.

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::optional greeting\nPASS example.ms::optional greeting\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn greeting(name: String?) String:
    if let value = name:
        return "Hello, {value}!"
    return "Hello, guest!"

test "optional greeting":
    try expect_equal(greeting("Ada"), "Hello, Ada!")
    try expect_equal(greeting(), "Hello, guest!")
```

```sh
ms test example.ms
```

```text
RUN example.ms::optional greeting
PASS example.ms::optional greeting
1 tests, 0 failed
```

- `T?` holds a value or `none`; `if let` handles the present value without an unwrap.
- Optional record fields default to `none`; chaining preserves absence instead of inventing a value.

## Optional chaining

<!-- manuscript-example: {"mode":"test","stdout":"RUN city.ms::optional city\nPASS city.ms::optional city\n1 tests, 0 failed\n"} -->
```manuscript {filename="city.ms"}
import expect_equal from "@std/test/test.ms"

type Address:
    city: String?

type Customer:
    address: Address?

test "optional city":
    let customer = Customer(Address("Paris"))
    if let size = customer.address?.city?.length():
        try expect_equal(size, 5)
    else:
        return error(Error("expected a city"))
```

```sh
ms test city.ms
```

```text
RUN city.ms::optional city
PASS city.ms::optional city
1 tests, 0 failed
```

- `?.` skips the rest of the chain on absence and flattens an already-optional member.
- Mutating through a chain requires a mutable owner; clone an owned field before moving it out.

## Handling errors

<!-- manuscript-example: {"mode":"test","stdout":"RUN port.ms::parse a port\nPASS port.ms::parse a port\n1 tests, 0 failed\n"} -->
```manuscript {filename="port.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn port_number(text: String) Int!:
    return ok(try text.parse_int().ok_or(Error("expected digits", kind: "EINVAL")))

test "parse a port":
    try expect_equal(try port_number("8080"), 8080)
    let cause = try expect_error(port_number("oops"))
    try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test port.ms
```

```text
RUN port.ms::parse a port
PASS port.ms::parse a port
1 tests, 0 failed
```

- `ok_or(cause)` evaluates its cause eagerly; `ok_or_else` creates it only on absence.
- Bare `ok_or()` supplies `Error` with kind `"ENOENT"` and the call’s source position.

<span id="passing-optional-arguments"></span><span id="checking-and-extracting-values"></span><span id="converting-absence-to-a-result"></span><span id="data-modeling"></span>

Next: [type checking](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-check/src/checker.rs); [expected errors](../errors/results.md).
