+++
title = "Start here: your first program"
weight = 1
+++

# Build and run your first program

[Book index](_index.md)

This walkthrough uses the hello project included in
[Manuscript release archives](https://github.com/manuscript-lang/manuscript/releases)
and the repository. Download and extract the archive for your OS and architecture,
or build from a source checkout as described below. `ms` embeds its native build
tools and needs no separate Go installation. Run the commands from the extracted
directory or repository root. In Windows PowerShell, use `.\ms.exe` instead of
`./ms`. You do not need Hugo to compile Manuscript programs.

## 1. Get the command-line tool

Release archives already contain the self-contained `ms` binary. To build it
from a source checkout on macOS or Linux:

```sh
make build
```

This downloads and verifies the pinned Go SDK locally on first use and creates
the self-contained `ms` executable. Initial setup needs Make, curl, tar, a SHA-256
utility, and Internet access. You can then copy only `ms` anywhere on `PATH`.
Its first native command unpacks the reduced embedded build payload into the user
cache; later commands reuse it without downloads. Native compilation disables CGO.

## 2. Check the example and pin its build tools

```sh
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
```

`check` reports source errors without running the program. `lock` creates or updates the project's `ms.lock` file, which records the compiler/runtime and Go toolchain/target used by native builds. Run `lock` again after changing those tools.

The project settings in `examples/hello/ms.toml` tell the compiler where to start:

```toml
[project]
name = "hello"
source = "./src"
entry = "./src/main.ms"
```

These paths are relative to the project manifest. The entry file is `examples/hello/src/main.ms`.

## 3. Run the program

```sh
./ms run examples/hello/ms.toml -- first second
```

Expected output:

```text
Arguments: 2
```

The `--` separates compiler options from arguments for your program. Here, `first` and `second` are the two program arguments.

## 4. Read the source

The complete entry module is:

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

Read it from top to bottom:

- `import` makes the standard `Process` type available in this file.
- `export fn main` defines the application's entry function. The CLI host passes in `process`; the returned integer becomes the exit code.
- `let` names a value. The string inserts the argument count inside `{...}` and ends with a newline, `\n`.
- `process.stdout` gives access to standard output. `write` takes a named `data` argument containing bytes, so `to_bytes()` converts the text first.
- `write` returns a `Result`. The `match` handles both outcomes: success returns exit code `0`, and failure returns `1`. The `_` means this example ignores the outcome's payload.

Four spaces start each nested block. Functions with multiple parameters name every supplied argument. A single-parameter function may omit its argument label.

## 5. Build a standalone executable

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
```

You should see the same output. `ms run` builds and runs a temporary executable; `ms build` leaves an executable you can run again.

Native builds bundle their pinned dependencies. `MANUSCRIPT_CACHE_DIR` selects
a different writable cache directory. `MANUSCRIPT_GO` explicitly selects an
alternative Go executable. For other commands and development checks, see the
[repository README](https://github.com/manuscript-lang/manuscript/blob/main/README.md).

## Where to go next

Continue with [source structure](core-language/basics/syntax.md), [bindings](core-language/basics/bindings.md), and [function calls](core-language/functions/declarations-and-calls.md). The [glossary](glossary.md) explains terms used throughout the book. The [implementation coverage](https://github.com/manuscript-lang/manuscript/blob/main/IMPLEMENTATION.md) lists supported features and remaining limits.
