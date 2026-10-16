+++
title = "Write idiomatic Manuscript"
weight = 4
+++

# Write idiomatic Manuscript

Once you can run a program and test it, these habits keep the next change easy
to understand. Follow the linked references when you need the exact rules.

## Make outcomes explicit

Use `Optional[T]` when a value may be missing and `Result[T, E]` when a failure
needs an explanation. Propagate errors with `try`. Use `if let` when you only
need a present value or successful result; a Result's error is discarded in
this form. Use `match` when you need to inspect the cause, and `unwrap_or` when
absence has a sensible default.

Keep one exit-status boundary in `main`. Helpers can return a domain error or
use `Error` as a common boundary. Keep matches flat: return early, propagate
with `try`, or extract a small helper instead of nesting another match.
See [error handling](../core-language/errors/_index.md).

## Let types describe your data

Read known JSON shapes with `parse[T]`. Unknown members are ignored by default;
pass `ignore_unknown_fields: false` when accepting them would be a mistake.
Use string interpolation to format values and structured fields when
[logging](../standard-library/logging.md).

Test the outcomes directly, and apply `try` to each assertion so a failed
check fails the test:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal, expect_error} from "@std/testing.ms"
import {parse, JsonError} from "@std/json.ms"

type Config:
    port: Int = 8080

fn port_of(text: String) -> Result[Int, Error]:
    let config = try parse[Config](text)
    return ok(config.port)

test "configuration defaults":
    try expect_equal(try port_of("\{\}"), 8080)
    try expect_equal(try port_of("\{\"port\": 9000\}"), 9000)

test "configuration rejects a wrong type":
    let cause = try expect_error(parse[Config]("\{\"port\": true\}"))
    try expect_equal(cause, JsonError.InvalidData)
```

The [testing guide](testing.md) covers selecting cases, checking faults, and
sharing setup. The [serialization guide](../standard-library/formats.md#json-behavior)
defines how fields and defaults are decoded.

## Keep ownership visible

Use `with` to keep a file, connection, or task group open for the block that
uses it. Cleanup also runs on early returns and errors. A captured reference
does not keep a resource open; acquire it inside the operation that needs it.
See [managing resources](../core-language/cleanup/_index.md).

Assignment shares records and collections. Call `.clone()` when you need
independent outer storage, and remember that nested values stay shared.
When concurrent work reads and mutates the same data, use the same
synchronization object through every alias. See
[mutation and references](../core-language/types/references.md) and
[sharing data](../concurrency/sharing.md).
