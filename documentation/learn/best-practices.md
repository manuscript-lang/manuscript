+++
title = "Write idiomatic Manuscript"
weight = 4
+++

# Write idiomatic Manuscript

Habits that keep the next change easy to understand.

## Make outcomes explicit

Use `Optional[T]` when a value may be missing and `Result[T, E]` when a failure
needs an explanation. Propagate errors with `try`. Use `if let` when you only
need a present value or successful result; a Result's error is discarded in
this form. Use `is_error()` with `err()` when you need to inspect the
cause, and `get(default)` when absence has a sensible default.

See [error handling](../core-language/errors/_index.md).

## Let types describe your data

Read known JSON shapes with `parse[T]`. Unknown members are ignored unless you pass `ignore_unknown_fields: false`. Apply `try` to each assertion so a failed check fails the test:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal, expect_error from "@std/test.ms"
import parse, JsonError from "@std/json.ms"

type Config:
    port: Int = 8080

fn port_of(text: String) Result[Int, Error]:
    return ok(try parse[Config](text) | .port)

test "configuration defaults":
    try expect_equal(try port_of("\{\}"), 8080)
    try expect_equal(try port_of("\{\"port\": 9000\}"), 9000)

test "configuration rejects a wrong type":
    try expect_error(parse[Config]("\{\"port\": true\}")) | try expect_equal(JsonError.InvalidData)
```

See the [testing guide](testing.md) for more.

## Keep ownership visible

- A file or connection stays open until the end of the scope that owns it; cleanup runs on early returns and errors. Acquire resources inside the operation that needs them. See [managing resources](../core-language/cleanup/_index.md).
- Parameters can borrow values; consuming a value moves it at its last use. `.clone()` makes an explicit copy. Mutate through `var` bindings and `var` parameters. See [values and references](../core-language/types/references.md) for the exact rules.
