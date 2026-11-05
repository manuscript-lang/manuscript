+++
title = "Coming from Go"
weight = 2
+++

# Coming from Go

Manuscript shares Go's taste for small languages, one formatter, and a single tool that builds. It differs in making error handling and memory part of the type system.

| In Go | In Manuscript |
| --- | --- |
| `(int, error)` and `if err != nil` | `Int!`, with `try` to pass an error up |
| `nil` pointers and zero values | `T?` for absence; no null |
| `struct` and `interface` | `type` with defaults; `interface` satisfied by methods in `impl` blocks |
| goroutines and channels | [Promises](../core-language/concurrency/promises.md), streams, and [pipes](../core-language/concurrency/streams.md#pipes) |
| `defer` | A [scope](../core-language/cleanup/scopes.md) closes what is bound in it |
| garbage collector | One owner per value, freed at its last use |
| `go build`, `go test`, `gofmt` | `ms build`, `ms test`, `ms fmt` |

## Errors without the boilerplate

Go's version of this function returns two values and checks the second at each step. Here the `!` carries the error and `try` forwards it:

<!-- manuscript-example: {"mode":"run","stdout":"port 8080\n"} -->
```manuscript
fn parse_port(text: String) Int!:
    let port = try text.parse_int().ok_or()
    if port < 1 or port > 65535:
        return error(Error("port out of range", kind: "ERANGE"))
    return ok(port)

export fn main() Int:
    let port = parse_port("8080")
    if port.is_error():
        print(port.err().message)
        return 1
    print("port {port.get()}")
    return 0
```

Unlike `err != nil`, dropping a `Result` is a compile error. `kind` plays the role of a sentinel error you can branch on. See [Expected failures with Result](../core-language/errors/results.md).

## Memory without a collector

There is no GC and no `&`. A value has one owner and moves at its last use; `var` marks mutation and `.clone()` marks a copy. Where Go shares a slice, Manuscript lends it or you clone it. [Ownership and borrowing](../core-language/types/references.md)

Next: [the guide](../guide/_index.md).
