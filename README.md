# Manuscript

The language for the agentic era.

API-first. Minimal syntax. Best-in-class tooling. See the [vision](VISION.md) for direction.

## How Manuscript is different

Most languages were shaped for human authors and then adapted to agents. Manuscript optimizes the language and the toolchain together for the loop an agent actually runs: write, check, fix, verify, ship.

| Optimization | What it means in practice |
| --- | --- |
| **A language with little to get wrong** | Statically typed, four-space blocks, no implicit conversion or truthiness, no special async syntax, and flat code: `|` pipe flows, `try`, and exhaustive `match`. Failure is a value: `Optional`, `Result`, and `try`. Cleanup is scoped with `with`. Fewer concepts means fewer first-draft errors and less to review. |
| **Tools that give evidence, not prose** | `--json` from `check`, `lint`, `test`, `build`, and `inspect`; `ms search_symbol` finds exact APIs, `ms guide` prints the cheat sheet, `ms verify` runs check, format, lint, and test in one result, and `ms review` and `ms diagram` show the effect of a change from the checked source, deterministically. |
| **Native code without a second language to manage** | Source compiles to a native executable with a bundled toolchain. The [performance benchmark](bench/perf/programs/results.md) compares generated code with hand-written Go; checked method calls are the largest gap and the current optimization target. |
| **One binary, always fresh** | `ms` is the compiler, formatter, linter, test runner, language server, debugger, and profiler. Nothing else to install. Rebuilds reuse a shared compiled-runtime workspace and replayed compile and link commands; no executable cache, so a stale binary never runs. |
| **Measured on real agents** | [`agent-bench`](bench/agent/README.md) runs the same challenges in Manuscript, Go, TypeScript, and Rust. Failures there drive diagnostics, docs, and the cheat sheet. The latest Haiku baseline has Manuscript behind the others on pass rate and cost, and closing that gap is the current work. |

See the [tooling guide](documentation/developer-tooling/implementation.md), [how it works](documentation/developer-tooling/how-it-works.md), and [VS Code integration](extensions/vscode/README.md).

Manuscript is statically typed. Write `.ms` files and build native executables with `ms`; the standard library covers files, processes, networking, HTTP, JSON, text, and time.

[Why Manuscript](documentation/learn/why-manuscript.md) · [Read the book](https://manuscript-lang.github.io/manuscript/) · [Take the tour](documentation/learn/tour.md) · [Download Manuscript](https://github.com/manuscript-lang/manuscript/releases)

## A first look

This complete program prints the number of arguments it receives:

```manuscript
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
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

fn describe(request: Request) String:
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
| Understand cleanup | [Resource lifetimes](documentation/core-language/cleanup/_index.md) and [runtime conventions](documentation/contributing/runtime-conventions.md) |
| Set up your editor or use source tools | [VS Code extension](extensions/vscode/README.md) and [tooling guide](documentation/developer-tooling/implementation.md) |
| Understand what `ms` bundles | [How it works](documentation/developer-tooling/how-it-works.md) |
| Choose optimization and debugging settings | [Build levels](documentation/developer-tooling/builds/build-levels.md) |

## Project status

Version 0.1: working compiler, runtime, standard library, test runner, formatter, and editor tooling, still evolving. External adapters, incremental frontend compilation, and some tooling APIs remain design work.

## Contribute

See the [architecture guide](documentation/contributing/architecture.md), [development and publishing](documentation/contributing/development.md), and [maintenance](documentation/contributing/maintenance.md). Routine checks: `make setup`, `make doctor`, `make verify`; `make verify-full` adds native validation.

Layout: `pkg/` (compiler, runtime), `cmd/` (entrypoints), `internal/` (helpers), `documentation/` (guides), [pkg/stdlib/](pkg/stdlib/intrinsics.ms) (standard declarations). The website builds into ignored `.artifacts/book/`.
