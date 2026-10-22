# Manuscript

A statically typed language that compiles to small, fast native executables, designed for the loop an agent runs: write, check, fix, verify, ship.

- **Fast.** Faster than hand-written Go on 26 of 31 benchmarks, and typically within 1.4x of Rust with overflow checks on. Linux release builds use LLVM.
- **Small and self-contained.** One `ms` binary compiles, formats, lints, tests, and serves your editor. No C toolchain needed on Linux and macOS; an HTTP server is about 4.4 MB.
- **Hard to get wrong.** Failure is a value, ownership is checked on every program, and there is no implicit conversion, truthiness, or async syntax. Agents pass 9 of 10 small challenges and 8 of 10 large applications on the [agent bench](bench/agent/results/summary-2026-10-21.md).

See the [vision](VISION.md) for direction.

## How Manuscript is different

Most languages were shaped for human authors and then adapted to agents. Manuscript optimizes the language and the toolchain together for the loop an agent actually runs: write, check, fix, verify, ship.

| Optimization | What it means in practice |
| --- | --- |
| **A language with little to get wrong** | Statically typed, four-space blocks, no implicit conversion or truthiness, no special async syntax, and flat code: `|` pipe flows, `try`, and exhaustive `match`. Failure is a value: `Optional`, `Result`, and `try`. Cleanup is scoped with `with`. Values have one owner: an ownership check runs on every program, moves happen at last use, `var` marks mutation at the declaration and the call, and `.clone()` copies explicitly. Fewer concepts means fewer first-draft errors and less to review. |
| **Tools that give evidence, not prose** | `--json` from `check`, `lint`, `test`, `build`, and `inspect`; `ms search_symbol` finds exact APIs, `ms guide` prints the cheat sheet, `ms verify` runs check, format, lint, and test in one result, and `ms review` and `ms diagram` show the effect of a change from the checked source, deterministically. |
| **Native code without a second language to manage** | Source compiles to a native executable, linked with a pinned `lld` bundled in `ms` on Linux and macOS (no C toolchain needed) and the system C compiler driver on Windows. Across 31 benchmarks, Manuscript takes 0.14x to 2.6x of hand-written Go's time: faster on 26, within 1.25x on 2 more, and up to 1.7x slower on the other 3 (string-keyed map updates, 2-D list indexing, map counting). Rust is faster on most rows, since it does not check Int overflow by default; with overflow checks on Manuscript is typically within 1.4x (sorting with a comparator, 1.2x), with larger gaps on string_append (4x) and chars (7.6x, where Rust iterates bytes without decoding). Release builds on Linux use LLVM when `clang` is installed. See the [program](bench/perf/programs/results.md), [competence](bench/perf/competence/README.md) and [kernel](bench/perf/kernels/README.md) benchmarks. |
| **One binary, always fresh** | `ms` is the compiler, formatter, linter, test runner, language server, and profiler. The native runtime is embedded. Linking uses a pinned static `lld` bundled in `ms`, so Linux (static musl executables) and macOS need no C compiler or SDK; Windows still links with the system C compiler driver (`clang`; `MS_LINKER` overrides it) until its bundled path lands. Unreached runtime and standard-library code is dropped at link time: on Linux x86_64 an empty program is about 0.45 MB and an HTTP server about 4.4 MB. |
| **Measured on real agents** | [`agent-bench`](bench/agent/README.md) runs the same challenges in Manuscript, Go, TypeScript, and Rust. Failures there drive diagnostics, docs, and the cheat sheet. With Claude Haiku 5.5 (2026-10-21), agents pass 9 of 10 small challenges and 8 of 10 large applications (3-5k lines) in Manuscript, against 10 of 10 small ones in TypeScript. Manuscript source is 1.30x TypeScript's size in LLM tokens. See the [results](bench/agent/results/summary-2026-10-21.md). |

See the [tooling guide](documentation/developer-tooling/implementation.md), [how it works](documentation/developer-tooling/how-it-works.md), and [VS Code integration](extensions/vscode/README.md).

Manuscript is statically typed. Write `.ms` files and build native executables with `ms`; the standard library covers files, processes, networking, HTTP, JSON, text, and time, plus collections beyond List, Map, and Set: `Queue`, `Deque`, `BitSet`, `SortedMap`, and `SortedSet`.

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

`if` is an expression, and `match` takes literal arms:

```manuscript
fn sign(value: Int) Int:
    return if value < 0: -1 else if value == 0: 0 else: 1

fn name(count: Int) String:
    match count:
        0: return "none"
        1: return "one"
        _: return "many"
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

## Build from source

Releases ship the Rust `ms`. To build it from a checkout, install [rustup](https://rustup.rs) and a C compiler (`cc`; `clang` on Windows; the `ring` crate compiles C sources while building the runtime), then:

```sh
cargo build --release --locked -p ms-cli
target/release/ms run examples/hello/ms.toml -- first second
```

See the [Rust toolchain guide](documentation/contributing/rust-toolchain.md) for checks, crates, and behavior differences.

## Contribute

See the [architecture guide](documentation/contributing/architecture.md), [development and publishing](documentation/contributing/development.md), and [maintenance](documentation/contributing/maintenance.md). Routine checks: `make setup`, `make doctor`, `make verify`; `make verify-full` adds the conformance corpus, book, and distribution checks. Rust changes also run `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo nextest run --workspace`.

Layout: `crates/` (compiler, runtime, tooling), `documentation/` (guides), [stdlib/](stdlib/intrinsics.ms) (standard declarations). The website builds into ignored `.artifacts/book/`.
