# Manuscript

**The language for the agentic era.**

Review agent-written programs through simple types, explicit errors and visible ownership. Manuscript is in alpha; syntax and APIs may change.

[Get the compiler](documentation/learn/getting-started.md), then save this as `config.ms`:

<!-- manuscript-example: {"mode":"test","filename":"config.ms","stdout":"RUN config.ms::an unset port uses the default\nPASS config.ms::an unset port uses the default\n1 tests, 0 failed\n"} -->
```manuscript
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

type Config:
    port: Int?

fn port_from(text: String) Int!:
    let config = try parse[Config](text)
    if let port = config.port:
        return ok(port)

    return ok(8080)

test "an unset port uses the default":
    let port = try port_from("\{\"port\":null\}")
    try expect_equal(port, 8080)
```

```sh
ms test config.ms
```

```text
RUN config.ms::an unset port uses the default
PASS config.ms::an unset port uses the default
1 tests, 0 failed
```

- **Compiler-visible types:** a small type system with generics, checked interfaces, no `any` escape hatch and no runtime reflection API.
- **Batteries-included standard library:** files, HTTP, JSON, streams, processes, crypto and testing ship with `ms`.

## Understand what your agent built

Generate an offline HTML code map from the same file:

```sh
ms diagram config.ms --format html -o code-map.html
```

- Silently creates an offline source-and-types map.

## Check, build and share

Check the same file’s types, formatting, lint and tests:

```sh
ms verify config.ms
```

```text
check  passed
fmt    passed
lint   passed
test   passed
```

- See [build and share](documentation/developer-tooling/how-it-works.md).

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [Toolchain](documentation/developer-tooling/implementation.md) · [Vision](VISION.md)
