# Manuscript

**The language for the agentic era.**

Manuscript helps agents write programs that people can understand, check and run. A small type system with generics keeps data and operations visible to the compiler; actionable diagnostics guide repairs, and native executables turn straightforward code into deployable programs. Explicit errors, ownership and resource scopes keep the important decisions visible in review.

[Try Manuscript](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [Performance](bench/perf/README.md)

## Compiler feedback an agent can act on

Every diagnostic reads `cause; fix`, and a habit from another language is answered with the Manuscript spelling:

```text
count.ms:2:12: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
```

When the repair is mechanical, `ms check --fix` applies it. A runtime fault comes back from `ms test --json` as data with kind, values, position and trace. The agent does not need the manual in its context: `ms guide` gives a compact language cheat sheet, `ms search_symbol` answers one API question in bounded output, and `ms verify` is type checking, formatting checks, lint and tests in one exit code. [Commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents)

## Agent mistakes the toolchain catches

- **Memory:** one owner per value, moved at its last use, dropped deterministically, with borrows inferred. No collector, no lifetime annotations. Every `var` and `.clone()` is visible in the source. [References](documentation/core-language/types/references.md)
- **Compile errors:** a dropped `Result`, a `match` missing a case, a borrow that outlives its owner, literal overflow.
- **Runtime faults:** overflow, bounds, deadlock and skipped cleanup stop with a source trace. [Faults](documentation/core-language/errors/faults.md)
- **Concurrency:** any function can wait. `Promise` represents an operation with one result, streams carry successive values, and a `pipe` transfers them between owners. Dropping a promise cancels it and waits for completion; cancellation is cooperative at waits. [Concurrency](documentation/core-language/concurrency/_index.md)
- **Tests:** property tests draw inputs the agent did not think of and shrink failures; `ms test --fuzz 30s` turns them into a fuzzer. [Testing](documentation/learn/testing.md)

## Review agent-written changes

Open an interactive map of the code an agent produced:

```sh
ms diagram ms.toml --format html -o code-map.html
```

The single offline HTML file puts source, checked types, calls, control flow and ownership annotations together. Follow a call into its source or add `--diff change.patch` to highlight changed declarations. These are views of the checked program; use tests and profiling to examine its execution. [Interactive code map](documentation/developer-tooling/implementation.md#interactive-code-map)

`ms review --diff` ranks changes to contracts, error flow and resource scopes so a reader can focus their review. [Review report](documentation/developer-tooling/implementation.md#review-report)

## What Manuscript offers

- **A small, regular language:** indentation blocks, one way to do most things, and a few forms that compose. [Tour](documentation/learn/tour.md)\
  **Plain types:** records with defaults, enums (`Draft`, `Published(url)`) that `match` must cover, nominal types, and methods in `impl` blocks that satisfy an `interface`. [Types](documentation/learn/tour.md#types-for-application-data)\
  **Plain functions:** typed parameters and returns, labeled arguments and defaults, functions as values, and `|` pipes that read top to bottom. [Functions](documentation/learn/tour.md#functions)
- **Deterministic memory:** one owner per value, moves at last use, and deterministic drops, with borrows inferred. No collector, no lifetime annotations. [References](documentation/core-language/types/references.md)
- **Types the compiler can see:** a small type system with generics, no `any` escape hatch and no runtime reflection API. Interfaces express behavior through checked signatures, so reusable code stays available to compiler analysis. [Types and generics](documentation/core-language/types/generics.md)
- **Batteries-included standard library:** HTTP, JSON, TOML, YAML, CSV, crypto, processes and more, with Manuscript APIs and native primitives. Nothing to install for common work. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)
- **Explicit resource lifetimes:** bind a file or connection locally to close it when its owning scope exits, including early returns, faults and cancellation. Flush fallible writes explicitly to observe errors. [Cleanup](documentation/core-language/cleanup/scopes.md)
- **Explicit error handling:** `Result` and `Optional` instead of null and exceptions. `try` propagates an error, `if let` and `match` handle one, and a dropped `Result` is a compile error. [Errors](documentation/core-language/errors/propagation.md)
- **Exact numbers:** sized integers, `Float32`, and `Decimal` literals like `12.50d`; conversions are explicit. [Numbers](documentation/core-language/basics/numbers-and-booleans.md)

## Shaped by measured agent use

- **Agent benchmark:** the same challenges, from small programs to multi-thousand-line apps, in TypeScript, Go, Rust and Manuscript, graded on hidden tests. Tokens, turns, time and cost are recorded. [Agent benchmark](bench/agent/README.md)
- **Failures drive the design:** diagnostics, `ms guide` and `ms search_symbol` exist because of where agents got stuck, and results are published even where Manuscript trails.
- **Performance benchmark:** compiler and runtime against hand-written Go and Rust on kernels, data structures, JSON, CSV, workers and an HTTP server, with reproduction commands. [Performance benchmark](bench/perf/README.md)

## Fast code from the straightforward loop

Debug builds support a quick edit-check-run loop; release builds optimize the executable for deployment. See [build levels](documentation/developer-tooling/builds/build-levels.md) for optimization choices. The [performance suites](bench/perf/README.md) record revision-specific results, tradeoffs and reproduction commands for kernels, JSON, HTTP and other workloads.

Typed JSON reads a known shape directly into a record: field defaults handle omitted settings, and a wrong type returns an error. Native typed decoding avoids constructing a public `JsonValue` tree first. Use `JsonValue` when the shape is unknown. [JSON recipes](documentation/learn/common-tasks.md)

*Alpha. Syntax and APIs can change.*

## Put an agent to work

[Get the compiler](documentation/learn/getting-started.md), save this as `config.ms`, run `ms test config.ms`:

```manuscript
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

type Config:
    port: Int?

fn port_from(text: String) Result[Int, Error]:
    let config = try parse[Config](text)
    return ok(config.port.get(8080))

test "an unset port uses the default":
    let port = try port_from("\{\"port\":null\}")
    try expect_equal(port, 8080)
```

```text
RUN config.ms::an unset port uses the default
PASS config.ms::an unset port uses the default
1 tests, 0 failed
```

Then hand your agent a small CLI you need and watch it work through `ms guide`, `ms search_symbol` and the compiler's feedback.

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [Vision](VISION.md)
