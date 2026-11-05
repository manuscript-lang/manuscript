+++
title = "Coming from Python"
weight = 3
+++

# Coming from Python

Manuscript reads like Python at a glance: indentation blocks, `for ... in`, string interpolation, and a batteries-included standard library. The difference is that types are checked before the program runs, and the result is a native executable.

| In Python | In Manuscript |
| --- | --- |
| Exceptions, `try/except` | A `Result` return, written `T!`, and `try` to pass an error up |
| `None`, `Optional[str]` | `String?` |
| `@dataclass`, classes | `type` with fields and defaults; methods in `impl` blocks |
| `async def`, `await`, threads | No `async`: any function can wait, and a [`Promise`](../core-language/concurrency/promises.md) runs work |
| `with open(...) as f:` | Bind the file in a [scope](../core-language/cleanup/scopes.md); it closes on exit |
| Mutable lists shared by reference | One owner per value; `.clone()` is the only copy |
| `pip`, `venv`, `pytest`, `black` | One `ms` command checks, formats, tests and builds |

## Failure you cannot forget

Where Python raises, a Manuscript function returns an error the caller must handle:

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

A mistake such as passing text where a number is expected is a compile error with a repair, not a traceback at run time. See [Expected failures with Result](../core-language/errors/results.md).

## Data without dicts

Instead of a dict with string keys, declare a `type`. Missing fields take defaults, and `T?` marks a value that may be absent:

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

The same shape decodes JSON directly with `parse[User](text)`. [Typed JSON](../learn/common-tasks.md#read-and-write-typed-json)

Next: [the language tour](../learn/tour.md).
