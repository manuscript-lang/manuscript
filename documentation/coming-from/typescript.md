+++
title = "Coming from TypeScript"
weight = 1
+++

# Coming from TypeScript

Manuscript keeps the parts of TypeScript you reach for most (inferred types, string interpolation, functions as values) and replaces the parts that fail at run time with checked ones.

| In TypeScript | In Manuscript |
| --- | --- |
| `string \| undefined`, `?.` | `String?`, [`?.`](../core-language/types/optionals.md) |
| `throw` and `try/catch` | A `Result` return, written `T!`, and `try` to pass an error up |
| `interface User { ... }` | `type User:` with fields and defaults |
| `async` and `await` | No `async`: any function can wait, and a [`Promise`](../core-language/concurrency/promises.md) runs work |
| `any`, `as` casts | None. Use a type, an interface, or `JsonValue` for unknown JSON |
| `const` and `let` | `let` and `var`, with `var` marking every mutation |
| npm, `tsc`, a test runner | One `ms` command checks, formats, tests and builds |

## Errors are values

A function that can fail says so in its return type, and a caller cannot ignore it:

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

Nothing is thrown, so there is no stack of `catch` blocks to trace. Read [Expected failures with Result](../core-language/errors/results.md).

## Absent values

`T?` is an `Optional[T]`. Give a fallback with `get`:

<!-- manuscript-example: {"mode":"run","stdout":"no email\nada@example.com\n"} -->
```manuscript
type User:
    name: String
    email: String? = none

fn contact(user: User) String:
    return user.email.get("no email")

export fn main() Int:
    print(contact(User(name: "Sam")))
    print(contact(User(name: "Ada", email: "ada@example.com")))
    return 0
```

## What changes most

Objects are not shared by reference. Each value has one owner, and `.clone()` is the only copy. Passing a list to a function lends it, and the compiler tells you when you use something after moving it. [Ownership and borrowing](../core-language/types/references.md)

Next: [the guide](../guide/_index.md).
