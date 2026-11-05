+++
title = "Build a command-line greeting"
+++

# Build a command-line greeting

Review how a command turns a named argument into a greeting. APIs may evolve during alpha.

## Greet a named user

<!-- manuscript-example: {"mode":"run","filename":"greet.ms","stdout":"Hello, Ada!\n","args":["greet","Ada"]} -->
```manuscript {filename="greet.ms"}
import Arg, Command, command from "@std/cli.ms"
import arguments from "@std/os/process.ms"

type Greeting:
    name: String

fn greet(options: Greeting) Int!:
    print("Hello, {options.name}!")
    return ok(0)

export fn main() Int:
    let greeting = command[Greeting](
        name: "greet", args: [Arg("name")], run: fn options: greet(options)
    )
    return Command(name: "tool", children: [greeting]).execute(arguments())
```

```sh
ms run greet.ms -- greet Ada
```

```text
Hello, Ada!
```

See the [API reference](../reference/cli.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
