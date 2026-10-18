+++
title = "Write idiomatic Manuscript"
weight = 4
+++

# Write idiomatic Manuscript

Habits that keep the next change easy to understand.

## Make outcomes explicit

- `Optional[T]` for a value that may be missing; `Result[T, E]` when failure needs a cause.
- Propagate with `try`; use `unwrap_or` when absence has a sensible default.
- `if let` takes a present value or success and discards a Result's error; read it with `is_error()` and `unwrap_error()`.
- Do not `match` a `Result` or `Optional`.
- Keep one exit-status boundary in `main`, and keep matches flat: return early, `try`, or extract a helper.

See [error handling](../core-language/errors/_index.md).

## Let types describe your data

Read known JSON shapes with `parse[T]`. Unknown members are ignored unless you pass `ignore_unknown_fields: false`. Test outcomes directly, with `try` on each assertion:

Test the outcomes directly, and apply `try` to each assertion so a failed
check fails the test:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal, expect_error} from "@std/testing.ms"
import {parse, JsonError} from "@std/json.ms"

type Config:
    port: Int = 8080

fn port_of(text: String) Result[Int, Error]:
    let config = try parse[Config](text)
    return ok(config.port)

test "configuration defaults":
    try expect_equal(try port_of("\{\}"), 8080)
    try expect_equal(try port_of("\{\"port\": 9000\}"), 9000)

test "configuration rejects a wrong type":
    let cause = try expect_error(parse[Config]("\{\"port\": true\}"))
    try expect_equal(cause, JsonError.InvalidData)
```

See the [testing guide](testing.md) for more.

## Keep ownership visible

- `with` keeps a file, connection, or task group open for its block; cleanup runs on early returns and errors. Acquire resources inside the operation that needs them. See [managing resources](../core-language/cleanup/_index.md).
- Assignment shares records and collections. `.clone()` copies the outer storage only; nested values stay shared.
- Concurrent readers and writers must use the same synchronization object through every alias. See [mutation and references](../core-language/types/references.md).
