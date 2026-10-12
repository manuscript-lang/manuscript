# Manuscript

The language for the agentic era.

API-first. Minimal syntax. Best-in-class tooling.

## Design principles

- **API first, minimal syntax.** Design the operation and its contract before inventing a language construct. Concurrency, scheduling, synchronization, and host services belong in imported APIs; new behavior should reuse ordinary calls and values wherever possible.
- **Optimize for AI writing code and humans understanding it.** Favor consistent compositions and visible dependencies. A change should be understandable from the source and the contracts it uses.
- **Treat completion as a contract.** Starting work also defines cancellation, joining, and cleanup. Design failure and shutdown behavior alongside the successful path.
- **Keep one source of truth for agents and tools.** Standard declarations define the APIs the compiler checks. Navigation and API references use those declarations; inspection and diagrams come from checked programs.
- **Build tooling alongside the language.** Every language decision should work through checking, editing, inspection, debugging, and profiling. Give agents structured answers and humans source-level explanations.

## What these choices bring to the table

| Manuscript's choice | What it gives you |
| --- | --- |
| **Concurrency through ordinary functions** | One function kind can wait for work. Imported `parallel` and `Background` APIs accept ordinary function values, so the same function can participate in sequential calls, joined work, or a service. |
| **Scheduling that follows the same model** | `sleep`, `after`, and `every` share the time API; scheduled work uses one scoped `Timer`. Callbacks follow the ordinary function and lifetime rules. |
| **Work and cleanup that finish together** | A parallel call waits for every started operation and its cleanup, including after a timeout. Background-service shutdown cancels and joins its work. `with` closes resources in reverse scope order, making shutdown ordering part of the program. |
| **Error identity preserved through composition** | Parallel operations retain their exact return values, including domain `Result` values. A domain error, an execution fault, and cancellation have distinct meanings; error translation uses explicit matching. |
| **APIs that tools can read as source** | Standard-library signatures live in Manuscript files that editors can navigate. The compiler supplies checked inspection, static call diagrams, and Markdown/JSON API exports, giving agents structured information about the code they are changing. |
| **A complete native build tool in one binary** | `ms` bundles the build tools, runtime, and pinned dependencies. After installation, agents can check, build, run, and test native programs without separately provisioning Go or downloading build dependencies. |

## Best-in-class tooling for agents and humans

Manuscript's tools share the compiler's understanding of the program:

- **Agents get structured evidence.** JSON diagnostics and checked source inspection expose symbols, call sites, source hashes, and effects. Static call diagrams and Markdown/JSON API exports make the program and its dependencies inspectable.
- **Editors understand the contracts.** Typed completion works in unfinished calls; named arguments and auto-imports follow checked scope. Project-wide rename checks the proposed edits before returning them. Standard-library definitions are navigable Manuscript source.
- **Runtime behavior stays connected to source.** Native debugging through Delve shows `.ms` frames, values, and execution/service state. CPU and heap profiles and execution traces carry source and work attribution; profile bundles retain the executable and matching metadata.

See the [tooling guide](documentation/developer-tooling/implementation.md) and [VS Code integration](extensions/vscode/README.md) for setup and current limits.

Manuscript is statically typed. Write `.ms` files, compile them to Go, and run them as native executables.

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
| Choose optimization and debugging settings | [Build levels](documentation/compiler/builds/build-levels.md) |

## Project status

Manuscript is at version 0.1, with a working compiler, runtime, standard library, native test runner, formatter, and editor tooling. The language and tools are still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work. Check [implementation coverage](documentation/implementation.md) for supported features and current limits.

## Contribute

The [architecture guide](documentation/contributing/architecture.md) maps the compiler and runtime. [Development and publishing](documentation/contributing/development.md) covers setup, checks, generated documentation, and releases.

Use `make setup`, `make doctor`, and `make verify` for routine development; `make verify-full` runs native validation. Read [maintenance and compatibility](documentation/contributing/maintenance.md) for pin updates and releases.

Language guides live in `documentation/`, and standard declarations live in [stdlib/](stdlib/README.md). The website is generated into ignored `.artifacts/book/` and deployed through GitHub Pages artifacts.
