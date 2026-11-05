# Manuscript: The language for the agentic era.

Review agent-written programs through compiler-visible types and explicit errors; Manuscript is in alpha, and syntax/APIs may change.

<!-- manuscript-example: {"mode":"run","filename":"config.ms","stdout":"Port: 8080\n"} -->
```manuscript {filename="config.ms"}
import parse from "@std/data/json.ms"

type Config:
    port: Int = 8080

fn read_port(text: String) Int!:
    let config = try parse[Config](text)
    return ok(config.port)

export fn main() Int:
    match read_port("\{\}"):
        ok(port):
            print("Port: {port}")
            return 0
        error(cause):
            print(cause.message)
            return 1
```

```sh
ms run config.ms
```

```text
Port: 8080
```

- A small type system with generics, no `any` or runtime reflection keeps types available to compiler analysis.
- The batteries-included standard library supplies typed JSON; `let` and scope-end drop keep ownership explicit.

## Human understanding

Generate an offline map of the same checked source:

```sh
ms diagram config.ms --format html -o code-map.html
```

- Silently creates `code-map.html` with source, types and calls.

## Direction

- Make real applications productive with the libraries and integrations they need.
- Keep agent generation, human review and delivery in one coherent workflow.

[Run a first program](documentation/learn/getting-started.md) · [Build and share](documentation/developer-tooling/how-it-works.md) · [Measured agent use](bench/agent/README.md)
