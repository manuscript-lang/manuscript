# Manuscript

The language for the agentic era.

API-first. Minimal syntax. Best-in-class tooling.

Read the [Manuscript vision](VISION.md) for long-term design direction, while respecting the current technical contracts documented in the language and tooling guides.

## Design principles

- **API first.** Keep syntax small. Express concurrency, scheduling, synchronization, and host services through imported APIs that compose with ordinary functions and values.
- **Agents write; humans understand.** Make contracts and dependencies visible in source. Favor familiar, consistent forms that make generated changes easy to review.
- **Fewer concepts, more composition.** Add a mechanism only when existing ones cannot express the problem clearly. Reuse the same rules across APIs so each addition has less to learn and more to build on.

## Tooling for agents and humans

Manuscript's tools share the compiler's understanding of the program:

- **Agents get structured evidence.** `--json` output from `check`, `lint`, `test`, `build`, and `inspect` gives diagnostics, symbols, call sites, source hashes, and effects. `ms search_symbol` finds project and standard-library APIs by name or words, and `ms guide` prints a language cheat sheet. Static call diagrams and Markdown/JSON API exports make the program and its dependencies inspectable.
- **Editors understand the contracts.** Typed completion works in unfinished calls; named arguments and auto-imports follow checked scope. Project-wide rename checks the proposed edits before returning them. Standard-library definitions are navigable Manuscript source.
- **Debugging and profiling stay connected to source.** `ms debug` and the VS Code adapter step through `.ms` lines and render Manuscript values. CPU and heap profiles and execution traces carry source attribution.

See the [tooling guide](documentation/developer-tooling/implementation.md) and [VS Code integration](extensions/vscode/README.md) for setup and current limits.

Manuscript is statically typed. Write `.ms` files and build native executables with `ms`; the standard library covers files, processes, networking, HTTP, JSON, text, time, and concurrency.

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

## More of the language

Optionals unwrap with `if let`, and typed JSON maps text to and from your own types:

```manuscript
type Request:
    model: String
    user: Optional[String]

fn describe(request: Request) -> String:
    if let name = request.user:
        return "{request.model} for {name}"
    else:
        return "{request.model} for nobody"
```

`json.stringify[T]` and `json.parse[T]` from `@std/json.ms` convert such types to and from JSON; unknown members are ignored by default. The [language tour](documentation/learn/tour.md) covers types, alternatives, generics, `try`, and tests.

## Try it

Download and extract the [release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture. It includes `ms` and the hello project shown above. Nothing else needs to be installed: `ms` builds and runs programs on its own, and you can copy the binary anywhere on `PATH`.

From the extracted directory, run:

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

In Windows PowerShell, use `.\ms.exe` instead of `./ms`.

```text
Arguments: 2
```

`check` validates the source. `run` builds a temporary executable and passes it the arguments after `--`.

To start your own project, run `./ms init my-app`. To keep a standalone executable or run the included test:

```sh
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

Use `./ms --help` to list commands, or `./ms help run` for a command's options and examples. Every command supports `--help`. `./ms fmt` formats source and `./ms lint` reports style and correctness findings.

Follow [your first program](documentation/learn/getting-started.md) for a walkthrough of the source and project manifest.

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn the language | [Language tour](documentation/learn/tour.md) and [core language](documentation/core-language/_index.md) |
| Find a standard type or function | `ms search_symbol <name or words>`, [Standard library](https://manuscript-lang.github.io/manuscript/standard-library/) and [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) |
| Understand cleanup and concurrent work | [Resource lifetimes](documentation/core-language/cleanup/_index.md) and [concurrency](https://manuscript-lang.github.io/manuscript/concurrency/) |
| Set up your editor or use source tools | [VS Code extension](extensions/vscode/README.md) and [tooling guide](documentation/developer-tooling/implementation.md) |
| Understand build pins and caches | [Reproducible builds](documentation/developer-tooling/builds/reproducibility.md) |
| Choose optimization and debugging settings | [Build levels](documentation/developer-tooling/builds/build-levels.md) |

## Project status

Manuscript is at version 0.1, with a working compiler, runtime, standard library, native test runner, formatter, and editor tooling. The language and tools are still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work. Each guide describes its own supported behavior and limits.

## Contribute

The [architecture guide](documentation/contributing/architecture.md) maps the compiler and runtime. [Development and publishing](documentation/contributing/development.md) covers setup, checks, generated documentation, and releases.

Use `make setup`, `make doctor`, and `make verify` for routine development; `make verify-full` runs native validation. Read [maintenance and compatibility](documentation/contributing/maintenance.md) for pin updates and releases.

Compiler and runtime packages live in `pkg/`, command entrypoints in `cmd/`, and private helpers in `internal/`. Language guides live in `documentation/`, and standard declarations live in [pkg/stdlib/](pkg/stdlib/intrinsics.ms). The website is generated into ignored `.artifacts/book/` and deployed through GitHub Pages artifacts.
