# Manuscript

The language for the agentic era.

API-first. Minimal syntax. Best-in-class tooling.

See the [vision](VISION.md) for long-term direction.

## Design principles

- **API first.** Small syntax; concurrency, scheduling, and host services come from imported APIs.
- **Agents write; humans understand.** Contracts and dependencies are visible in source, in familiar, reviewable forms.
- **Fewer concepts, more composition.** Add a mechanism only when existing ones cannot express the problem.

## Tooling for agents and humans

Tools share the compiler's understanding of the program:

- **Agents get structured evidence.** `--json` from `check`, `lint`, `test`, `build`, and `inspect` reports diagnostics, symbols, call sites, hashes, and effects. `ms search_symbol` finds APIs, `ms guide` prints a cheat sheet, and `ms review` shows where to look.
- **Editors understand the contracts.** Typed completion, checked auto-imports, safe project-wide rename, and navigable standard-library source.
- **Debugging stays on source.** `ms debug`, the VS Code adapter, profiles, and traces map to `.ms` lines.

See the [tooling guide](documentation/developer-tooling/implementation.md) and [VS Code integration](extensions/vscode/README.md).

Manuscript is statically typed. Write `.ms` files and build native executables with `ms`; the standard library covers files, processes, networking, HTTP, JSON, text, time, and concurrency.

[Read the book](https://manuscript-lang.github.io/manuscript/) · [Take the tour](documentation/learn/tour.md) · [Download Manuscript](https://github.com/manuscript-lang/manuscript/releases)

## A first look

This complete program prints the number of arguments it receives:

```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(data: message.to_bytes()).is_error():
        return 1
    return 0
```

`main`'s return value is the exit code; `is_error()` tests the write.

## More of the language

Optionals unwrap with `if let`; typed JSON maps text to your types:

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

`json.parse[T]` and `json.stringify[T]` (`@std/json.ms`) convert such types; unknown members are ignored by default. The [tour](documentation/learn/tour.md) covers more.

## Try it

Extract the [release archive](https://github.com/manuscript-lang/manuscript/releases). It includes `ms` and the hello project; nothing else to install.

From the extracted directory, run:

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

On Windows PowerShell, use `.\ms.exe`.

```text
Arguments: 2
```

`check` validates source; `run` builds a temporary executable and passes it arguments after `--`.

Start a project with `./ms init my-app`, or keep an executable and run the test:

```sh
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

`./ms --help` lists commands; `fmt` formats and `lint` reports findings. See [your first program](documentation/learn/getting-started.md).

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn the language | [Language tour](documentation/learn/tour.md) and [core language](documentation/core-language/_index.md) |
| Find a standard type or function | `ms search_symbol <name or words>` and the [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) |
| Understand cleanup and concurrent work | [Resource lifetimes](documentation/core-language/cleanup/_index.md) and [runtime concurrency semantics](documentation/contributing/concurrent-runtime.md) |
| Set up your editor or use source tools | [VS Code extension](extensions/vscode/README.md) and [tooling guide](documentation/developer-tooling/implementation.md) |
| Understand what `ms` bundles | [How it works](documentation/developer-tooling/how-it-works.md) |
| Choose optimization and debugging settings | [Build levels](documentation/developer-tooling/builds/build-levels.md) |

## Project status

Version 0.1: working compiler, runtime, standard library, test runner, formatter, and editor tooling, still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work.

## Contribute

See the [architecture guide](documentation/contributing/architecture.md), [development and publishing](documentation/contributing/development.md), and [maintenance](documentation/contributing/maintenance.md). Routine checks: `make setup`, `make doctor`, `make verify`; `make verify-full` adds native validation.

Layout: `pkg/` (compiler, runtime), `cmd/` (entrypoints), `internal/` (helpers), `documentation/` (guides), [pkg/stdlib/](pkg/stdlib/intrinsics.ms) (standard declarations). The website builds into ignored `.artifacts/book/`.
