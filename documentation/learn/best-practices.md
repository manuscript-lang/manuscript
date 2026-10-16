+++
title = "Best practices"
weight = 5
+++

# Best practices

- Return `Result[T, Error]` from anything that can fail; propagate with `try`. Keep one boundary in `main`, which returns the exit status.
- Unwrap `Optional` and `Result` with `if let`; use `unwrap_or` for a default. Avoid two-arm `match` on `some`/`none` (MSL108).
- Never nest `match`: early-return, `try`, or a small helper.
- Read JSON into a type with `parse[T]`. Unknown fields are ignored by default; pass `ignore_unknown_fields: false` to reject them.
- Format with `"{expr}"` and `toString()`, not concatenation.
- Scope resources with `with name = try open(...)`; never close by hand.
- Log structured fields with `record`, not formatted messages.
- In tests, `try` every check and let failures return as errors; don't `panic`, and never leave `expect_equal(...)` without `try`.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal} from "@std/testing.ms"
import {parse} from "@std/json.ms"

type Config:
    port: Int

fn port_of(text: String) -> Result[Int, Error]:
    let config = try parse[Config](text)
    return ok(config.port)

fn label(name: Optional[String]) -> String:
    if let value = name:
        return "Hello, {value}"
    return "Hello!"

test "defaults":
    try expect_equal(try port_of("\{\"port\": 8080, \"extra\": true\}"), 8080)
    try expect_equal(label(some("Ada")), "Hello, Ada")
    try expect_equal(label(none), "Hello!")
```

See [results](../core-language/errors/results.md), [conditionals](../core-language/control-flow/conditionals.md#unwrapping-an-optional-or-result), [cleanup](../core-language/cleanup/_index.md), [logging](../standard-library/logging.md), and [testing](testing.md).
