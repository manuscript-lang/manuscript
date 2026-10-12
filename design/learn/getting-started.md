+++
title = "Get started"
weight = 1
+++

# Get started

Install Go 1.25 or newer and clone the repository. Run these commands from its root:

```sh
go build -o ms ./cmd/ms
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

The program prints `Arguments: 2`. The lock command pins the compiler, runtime, Go toolchain, and target; rerun it after changing those inputs.

## Your first application

The hello project's `src/main.ms` is a complete application:

```text
import Process from "@std/cli.ms"

export fn main(process: Process) -> Int:
    let message = "Arguments: {process.arguments.length()}\n"
    match process.stdout.write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
```

The import names the one standard declaration this module needs. `main` receives the process capability, including arguments and output streams. `let` binds a value with an inferred local type. String interpolation inserts the argument count. `write(data: ...)` names its argument and returns a `Result`; the match handles success and failure. The returned integer becomes the exit status.

Indentation defines blocks. A function with one parameter permits calls such as `process.stdout.write(message.to_bytes())` or `process.stdout.write(data: message.to_bytes())`. Functions with multiple parameters require labels on every supplied argument; zero-parameter calls use `()`. Public functions are explicitly exported, and each `.ms` file is a module.

## Build and inspect

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
./ms emit examples/hello/ms.toml -o main.go
./ms inspect examples/hello/ms.toml -o inspection.json
./ms diagram examples/hello/ms.toml -o calls.mmd
```

`build` produces a native executable. `emit` exposes the generated Go program. `inspect` produces structured source information; `diagram` captures static calls. To check formatting, run `./ms fmt examples/hello/src/main.ms --check`.

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
