+++
title = "Get started"
weight = 1
+++

# Get started

Download and extract the archive for your operating system and architecture from
[Manuscript Releases](https://github.com/manuscript-lang/manuscript/releases).
The `ms` binary includes the compiler, its native build tools, and all native build
dependencies. You do not need to install Go or download packages to build, run,
or test Manuscript programs. You can copy `ms` (`ms.exe` on Windows) anywhere on
`PATH` without companion files. It automatically prepares its embedded build
payload in the user cache on first native use. CGO is disabled.

Run these commands from the extracted directory. In Windows PowerShell, replace
`./ms` with `.\ms.exe`:

```sh
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

The program prints `Arguments: 2`. The lock command pins the compiler, runtime, Go toolchain, and target; rerun it after changing those inputs.

If you prefer a source checkout on macOS or Linux, clone the repository and run
`make build`. The first build downloads and verifies Go into `toolchain/go/`
automatically; later builds reuse it. Make, curl, tar, and a SHA-256 utility are
needed for this initial setup. The resulting `./ms` embeds only the native build
tools and references Manuscript needs and runs independently of the checkout.

## Your first application

The hello project's `src/main.ms` is a complete application:

```manuscript
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
./ms test examples/hello/test.ms
./ms emit examples/hello/ms.toml -o main.go
./ms inspect examples/hello/ms.toml -o inspection.json
./ms diagram examples/hello/ms.toml -o calls.mmd
```

`build` produces a native executable. `emit` exposes the generated Go program. `inspect` produces structured source information; `diagram` captures static calls. To check formatting, run `./ms fmt examples/hello/src/main.ms --check`.

Built executables run independently of the Manuscript installation. Native
compilation uses the embedded build tools automatically. `MANUSCRIPT_GO`
explicitly selects an alternative Go executable. `MANUSCRIPT_CACHE_DIR` selects
a different writable cache directory.

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
