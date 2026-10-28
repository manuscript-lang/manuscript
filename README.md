# Manuscript

**The language for the agentic era.**

Manuscript starts from one premise: agents will write most of the code, and people have to understand, check and run it. An agent has a limited context, cannot hold a whole program in its head, and learns from the compiler one round trip at a time. Every design choice below exists because of that.

[Try Manuscript](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [Performance](bench/perf/README.md)

## Compiler feedback an agent can act on

Every diagnostic reads `cause; fix`, and a habit from another language is answered with the Manuscript spelling:

```text
count.ms:2:12: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
```

When the repair is mechanical, `ms check --fix` applies it. A runtime fault comes back from `ms test --json` as data with kind, values, position and trace. The agent does not need the manual in its context: `ms guide` is the whole language in 4 KB, `ms search_symbol` answers one API question in bounded output, and `ms verify` is check, format, lint and test in one exit code. [Commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents)

## Agent mistakes the toolchain catches

- **Memory:** one owner per value, moved at its last use, dropped deterministically, with borrows inferred. No collector, no lifetime annotations. Every `var` and `.clone()` is visible in the source. [References](documentation/core-language/types/references.md)
- **Compile errors:** a dropped `Result`, a `match` missing a case, an unclosed `Closeable`, literal overflow.
- **Runtime faults:** overflow, bounds, deadlock and skipped cleanup stop with a source trace. [Faults](documentation/core-language/errors/faults.md)
- **Concurrency:** any function can wait, and tasks live in a `with` block that cancels what is still running, so generated code cannot leak one. [Concurrency](documentation/core-language/concurrency/_index.md)
- **Tests:** property tests draw inputs the agent did not think of and shrink failures; `ms test --fuzz 30s` turns them into a fuzzer. [Testing](documentation/learn/testing.md)

## Review agent-written changes

`ms review --diff` compares the checked program before and after and ranks changed contracts, error flow and `with` scopes by where a reader should look first. `ms diagram` draws call and flow graphs from the same analysis. [Review report](documentation/developer-tooling/implementation.md#review-report)

## What Manuscript offers

- **A small, regular language:** indentation blocks, one way to do most things, and a few forms that compose. Habits from other languages get a pointed diagnostic, not a new feature. [Tour](documentation/learn/tour.md)
- **Deterministic memory:** one owner per value, dropped at its last use, borrows inferred. No collector, no lifetime annotations. [References](documentation/core-language/types/references.md)
- **Static types, native code:** checked ahead of time and compiled to a native executable, with a fast debug loop and optimized release builds.
- **Batteries-included standard library:** HTTP, JSON, TOML, YAML, CSV, crypto, processes and more, written in Manuscript. Nothing to install for common work. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)
- **Cleanup you cannot forget:** resources close at scope end on every exit, including faults and cancellation. [Cleanup](documentation/core-language/cleanup/scopes.md)
- **Explicit where it matters:** `Optional` and `Result` instead of null and exceptions, sized and `Decimal` numbers, and `Shared[T]` for shared ownership. [Numbers](documentation/core-language/basics/numbers-and-booleans.md)

## Shaped by measured agent use

- **Agent benchmark:** the same challenges, from small programs to multi-thousand-line apps, in TypeScript, Go, Rust and Manuscript, graded on hidden tests. Tokens, turns, time and cost are recorded. [Agent benchmark](bench/agent/README.md)
- **Failures drive the design:** diagnostics, `ms guide` and `ms search_symbol` exist because of where agents got stuck, and results are published even where Manuscript trails.
- **Performance benchmark:** compiler and runtime against hand-written Go and Rust on kernels, data structures, JSON, CSV, workers and an HTTP server, with reproduction commands. [Performance benchmark](bench/perf/README.md)

## Fast code from the straightforward loop

Debug builds use Cranelift for a quick edit-check-run loop; release builds use LLVM. List loops are auto-vectorized, with an AVX2 copy chosen at run time on x86-64. Speed is comparable to Rust with overflow checks on, and Manuscript beat hand-written Go on all seven kernels. [Recorded runs and reproduction commands](bench/perf/README.md)

The standard library is about 14,000 lines of Manuscript across 40+ modules (HTTP, JSON, TOML, YAML, CSV, crypto, processes, and more), with Rust only for small primitives. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)

*Alpha. Syntax and APIs can change.*

## Put an agent to work

[Get the compiler](documentation/learn/getting-started.md), save this as `config.ms`, run `ms test config.ms`:

```manuscript
from "@std/json.ms" import parse
from "@std/test.ms" import expect_equal

type Config:
    port: Optional[Int]

def port_from(text: String) -> Result[Int, Error]:
    let config = try parse[Config](text)
    return ok(config.port.get(8080))

test "an unset port uses the default":
    let port = try port_from("{\"port\":null}")
    try expect_equal(port, 8080)
```

Then hand your agent a small CLI you need and watch it work through `ms guide`, `ms search_symbol` and the compiler's feedback.

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [Vision](VISION.md)
