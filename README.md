# Manuscript

A statically typed language for making programs easy to follow.

Manuscript makes function inputs, expected failures, resource cleanup, and concurrent work visible in source. Write `.ms` files, compile them to Go, and run them as native executables.

[Read the book](https://manuscript-lang.github.io/manuscript/) · [Take the tour](documentation/learn/tour.md) · [Download Manuscript](https://github.com/manuscript-lang/manuscript/releases)

## A first look

This complete program prints the number of arguments it receives:

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

Imports name the standard services the program uses. `let` infers the local value's type, and `match` handles both outcomes of the write. The integer returned by `main` becomes the program's exit code.

## Why Manuscript?

- **Readable calls.** Functions declare their input and output types. Calls with multiple parameters name each argument.
- **Explicit data and errors.** Nominal types distinguish domain concepts; alternatives require exhaustive matching. Expected failures use typed `Result` values.
- **Scoped cleanup.** A `with` block closes its registered resources when the scope ends, including on errors and cancellation.
- **Visible concurrency.** Ordinary calls run sequentially. Start concurrent work explicitly, join parallel operations, and give background work a service lifetime.
- **Native programs.** The compiler produces native executables through Go. The single `ms` binary bundles the build tools, runtime, and standard library it needs.

The [language tour](documentation/learn/tour.md) introduces the syntax. [Features and boundaries](documentation/learn/features.md) explains the design in more detail.

## Try it

Download and extract the [release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture. It includes `ms` and the hello project shown above. No separate Go installation or package downloads are needed to build and run programs; you can also copy the binary anywhere on `PATH`.

From the extracted directory, run:

```sh
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

In Windows PowerShell, use `.\ms.exe` instead of `./ms`.

```text
Arguments: 2
```

`check` validates the source. `lock` records the project's build pins; rerun it after changing Manuscript or the target toolchain. `run` builds a temporary executable and passes it the arguments after `--`.

To keep a standalone executable or run the included test:

```sh
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

Use `./ms --help` to list commands, or `./ms help run` for a command's options and examples. Every command supports `--help`.

Follow [your first program](documentation/getting-started.md) for a walkthrough of the source and project manifest. To build `ms` from a source checkout on macOS or Linux, run `make build`; initial setup needs Make, curl, tar, a SHA-256 utility, and Internet access to fetch the pinned Go SDK.

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn the language | [Language tour](documentation/learn/tour.md) and [core language](documentation/core-language/_index.md) |
| Find a standard type or function | [Standard library](documentation/standard-library/_index.md) and [API reference](documentation/standard-library/reference/_index.md) |
| Understand cleanup and concurrent work | [Resource lifetimes](documentation/ownership-and-cleanup/_index.md) and [concurrency](documentation/concurrency/_index.md) |
| Set up your editor or use source tools | [VS Code extension](extensions/vscode/README.md) and [tooling guide](documentation/developer-tooling/implementation.md) |
| Understand build pins and caches | [Reproducible builds](documentation/compiler/builds/reproducibility.md) |

## Project status

Manuscript is at version 0.1, with a working compiler, runtime, standard library, native test runner, formatter, and editor tooling. The language and tools are still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work. Check [implementation coverage](documentation/implementation.md) for supported features and current limits.

## Contribute

The [architecture guide](documentation/contributing/architecture.md) maps the compiler and runtime. [Development and publishing](documentation/contributing/development.md) covers setup, checks, generated documentation, and releases.

Language guides live in `documentation/`, and standard declarations live in [stdlib/](stdlib/README.md). The website in `docs/` is generated from those sources.
