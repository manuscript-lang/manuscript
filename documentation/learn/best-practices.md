+++
title = "Best practices"
weight = 5
+++

# Best practices

Idiomatic Manuscript is short because the defaults carry the weight: `Result` and `try` handle errors, `if let` unwraps, `with` cleans up, and `parse` reads typed data. Each section shows the concise form. Save a complete example to a `.ms` file and run it with `ms run`, or with `ms test` when it contains tests; `ms check`, `ms fmt`, and `ms lint` cover the rest.

## Return `Result` and propagate with `try`

Return `Result[T, Error]` from anything that can fail and let `try` pass the error up. Keep one error boundary in `main`, which returns the exit status. See [Results](../core-language/errors/results.md) and [propagation](../core-language/errors/propagation.md).

<!-- manuscript-example: {"mode":"run","stdout":"8080\n"} -->
```manuscript
import {parse} from "@std/json.ms"
import stdout from "@std/io.ms"

type Config:
    port: Int

fn load(text: String) -> Result[Config, Error]:
    return parse[Config](text)

fn run() -> Result[Unit, Error]:
    let config = try load("\{\"port\": 8080\}")
    try stdout().write("{config.port}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

`parse[Config]` builds a typed value directly and ignores unknown fields by default, so a document may carry extra keys without breaking the program. Pass `ignore_unknown_fields: false` when extra keys must be rejected.

## Unwrap with `if let`

`if let` binds the payload of an `Optional` or `Result` and takes an optional `else`. Prefer it to a two-arm `match` on `some` and `none`, which `ms lint` reports as MSL108. Use `unwrap_or` when a default value is enough. See [conditionals](../core-language/control-flow/conditionals.md#unwrapping-an-optional-or-result).

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal} from "@std/testing.ms"

fn greeting(name: Optional[String]) -> String:
    if let value = name:
        return "Hello, {value}"
    return "Hello!"

fn port(lookup: Result[Int, Error]) -> Int:
    if let value = lookup:
        return value
    return 8080

test "optional and result":
    try expect_equal(greeting(some("Ada")), "Hello, Ada")
    try expect_equal(greeting(none), "Hello!")
    try expect_equal(port(ok(3000)), 3000)
    try expect_equal(["a"].at(5).unwrap_or("none"), "none")
```

`if let` drops a `Result`'s error. Use `try` or `match` when the error matters.

## Keep `match` flat

Bind a payload with an early exit, use `try`, or call a small helper instead of nesting `match`. See [flat match flow](../core-language/control-flow/pattern-matching.md#keep-match-flow-flat).

## Let tests return errors

A `test` returns a `Result` implicitly: `try` a check and a failure becomes the test's error. Do not `panic` in a test. Bare `expect_equal(...)` without `try` checks nothing. See [testing](testing.md).

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal} from "@std/testing.ms"
import {parse} from "@std/json.ms"

type Point:
    x: Int
    y: Int

test "parse ignores unknown fields":
    let point = try parse[Point]("\{\"x\": 1, \"y\": 2, \"z\": 3\}")
    try expect_equal(point.x + point.y, 3)
```

## Convert values with `toString()` and interpolation

Every value has `toString()`, and `"{expr}"` interpolates any expression. Avoid manual concatenation.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {expect_equal} from "@std/testing.ms"

test "formatting":
    let count = 3
    try expect_equal(count.toString(), "3")
    try expect_equal("{count} items", "3 items")
```

## Scope resources with `with`

`with name = try open(...)` closes the resource when the block ends, on every path, so there is no manual `close`. See [cleanup](../core-language/cleanup/_index.md).

<!-- manuscript-example: {"mode":"run","args":["notes.txt"],"files":{"notes.txt":"hello\n"},"stdout":"hello\n","cases":[{"args":["missing.txt"],"exit_code":1}]} -->
```manuscript
import arguments from "@std/cli.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
import stdout from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    let path = arguments().at(0)
    if path.is_none():
        return error(FileSystemError.InvalidInput)
    with file = try filesystem().open(path.unwrap(), "r", 0):
        let bytes = try file.read_file()
        try stdout().write(bytes)
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

## Log structured fields

Create one logger and attach fields with `record` rather than formatting them into the message. Logging failures are `Result` errors, so `try` them like any other. See [logging](../standard-library/logging.md).

<!-- manuscript-example: {"mode":"run","stdout":"{\"level\":30,\"msg\":\"listening\",\"port\":8080}\n"} -->
```manuscript
import {create, record, stdout_transport, LogLevel} from "@std/log.ms"

type Listening:
    port: Int

fn announce() -> Result[Unit, Error]:
    with transport = stdout_transport():
        let logger = try create(transport: transport, timestamp: false)
        try record(logger: logger, level: LogLevel.Info, message: "listening", fields: Listening(port: 8080))
        return ok(unit)

export fn main() -> Int:
    match announce():
        ok(_): return 0
        error(_): return 1
```
