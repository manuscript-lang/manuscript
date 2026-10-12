+++
title = "Get started"
weight = 1
+++

# Get started

Download and extract the archive for your operating system and architecture from
[Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases).
The archive includes `ms`, its build tools, and runnable examples. Put `ms` on `PATH` to use it from any directory.

Run these commands from the extracted directory. In Windows PowerShell, replace
`./ms` with `.\ms.exe`:

```sh
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

The program prints `Arguments: 2`. The lock command pins the compiler, runtime, Go toolchain, and target; rerun it after changing those inputs.

From a source checkout, run `make build` to create `./ms`. See [development setup](../contributing/development.md) for prerequisites.

## Your first application

The hello project's `src/main.ms` is a complete application:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"
    match stdout().write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
```

The imports name the argument and standard-output accessors this module needs. The host calls `main()` with no arguments; the imported functions return its host data and services. `let` binds a value with an inferred local type. String interpolation inserts the argument count. `write(data: ...)` names its argument and returns a `Result`; the match handles success and failure. The returned integer becomes the exit status.

Indentation defines blocks. A function with one parameter permits calls such as `stdout().write(message.to_bytes())` or `stdout().write(data: message.to_bytes())`. Functions with multiple parameters require labels on every supplied argument; zero-parameter calls use `()`. Public functions are explicitly exported, and each `.ms` file is a module.

## Build and inspect

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
./ms test examples/hello/test.ms
./ms emit examples/hello/ms.toml -o main.go
./ms inspect examples/hello/ms.toml -o inspection.json
./ms diagram examples/hello/ms.toml -o calls.mmd
```

`build` produces a native executable. `emit` exposes the generated Go program. `inspect` produces structured source information; `diagram` captures static calls. To check formatting, run `./ms fmt examples/hello/src/main.ms --check`.

Built executables run independently of the Manuscript installation.

## Generate API documentation

```sh
./ms doc examples/hello/ms.toml -o api.md
./ms doc examples/hello/ms.toml --json -o api.json
./ms doc --stdlib -o stdlib.md
```

The generator documents checked public declarations and writes Markdown by default.
`--json` produces a versioned structured reference. Without `-o`, output goes to
stdout. It works from the shipped binary without installing Go. `--stdlib`
documents the standard library bundled with that version of the compiler.

Continue with [the language tour](tour.md).
