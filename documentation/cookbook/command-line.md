+++
title = "Command-line programs"
weight = 1
+++

# Command-line programs

Print output, read arguments and build a command with subcommands and flags. Each program is a complete `.ms` file: save it under the shown name and run the command from that directory ([getting started](../learn/getting-started.md)). `main` returns the exit status.

## Print a line

Save as `hello.ms`. `print` is available without an import and adds a newline.

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

```sh
ms run hello.ms
```

```text
Hello, Manuscript!
```

`print` returns `Unit`. The next recipe uses `stdout().write(...)` and `stdout().flush().wait()` to control text and flushing explicitly. These methods use the stream `Result` interface, but ordinary stdout does not expose native write errors through it. Use `stdout_bytes()` for byte output.

## Read command-line arguments

Save as `args.ms`. `arguments()` excludes the executable; values after `--` reach your program.

<!-- manuscript-example: {"mode":"run","args":["Sam","Ada"],"stdout":"Hello, Sam!\nHello, Ada!\n","cases":[{"stdout":""}]} -->
```manuscript
import arguments from "@std/os/env.ms"
import stdout from "@std/io/io.ms"

fn run() Result[Unit, Error]:
    for name in arguments():
        try stdout().write("Hello, {name}!\n")
    return stdout().flush().wait()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
```

```sh
ms run args.ms -- Sam Ada
```

```text
Hello, Sam!
Hello, Ada!
```

## Parse subcommands and flags

Save as `tool.ms`. `@std/cli/command.ms` resolves nested commands, typed flags and positional arguments, writes `--help`, and hands your handler a value of a type you define: each field is filled from the flag or argument with the same name (`dry-run` fills `dry_run`). Usage errors print a message and exit with status 2.

<!-- manuscript-example: {"mode":"run","args":["hello","Ada","-n","2"],"stdout":"Hello, Ada!\nHello, Ada!\n"} -->
```manuscript
import Arg, Command, Flag, FlagKind, command from "@std/cli/command.ms"
import stdout from "@std/io/io.ms"
import arguments from "@std/os/env.ms"

type Greeting:
    name: String
    times: Int

fn greet(options: Greeting) Result[Int, Error]:
    for round in 0..options.times:
        try stdout().write("Hello, {options.name}!\n")
    try stdout().flush().wait()
    return ok(0)

export fn main() Int:
    let hello = command[Greeting](
        name: "hello",
        about: "Print a greeting",
        flags: [Flag("times", FlagKind.Int, "n", "1", "Repeat count")],
        args: [Arg("name", "Who to greet")],
        run: fn options: greet(options)
    )
    return Command(name: "tool", about: "Example tool", children: [hello]).execute(arguments())
```

```sh
ms run tool.ms -- hello Ada -n 2
```

```text
Hello, Ada!
Hello, Ada!
```

Run `ms run tool.ms -- hello --help` to see the command’s arguments and flags.
