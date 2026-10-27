# Manuscript

**The language for the agentic era.**

Manuscript helps agents write correct, fast programs that are easy to review.

A small, regular language makes intent explicit. Strong types and ownership give the compiler more to check. Native builds support fast iteration and execution, while readable source keeps changes understandable.

[Try Manuscript](documentation/learn/getting-started.md) · [Explore the language](documentation/learn/tour.md) · [Performance results](bench/perf/README.md)

*Alpha: syntax and APIs can change. These examples follow current source; releases may lag. First builds download pinned tools. [Setup and platform requirements](documentation/learn/getting-started.md).*

## Catch mistakes before you run

Give your agent a compiler that checks assumptions you would otherwise have to chase through generated code.

**Keep wrong values out.** Strong types, simple generics and no built-in `any` prevent a `List[Int]` from quietly accepting a string. `Optional[T]` keeps “might be missing” in the type instead of leaving you to infer it from every caller.

**Make failure handling a visible choice.** Expected failures are `Result` values, not exceptions. The agent handles them or propagates them with `try`. A bare call that drops its `Result` is rejected, so ignoring failure requires an explicit choice. Missing `match` cases are caught before the unhandled path runs.

**Catch invalid mutation and missed cleanup.** `let` keeps data immutable; `var` marks where changes are allowed. Borrow checks reject conflicting access without lifetime annotations. Resource checks flag owned `Closeable` bindings left without cleanup or ownership transfer. `with` closes resources when its block exits, including on early returns and errors; task, worker and process groups keep concurrent work within explicit scopes.

**Give your agent a concrete repair target.** Diagnostics identify the cause, location and suggested fix; structured output and available `ms check --fix` edits support automated repair. `ms search_symbol` finds actual APIs, and `ms verify` checks types, formatting and lint, then runs tests. Tests and review still check whether the program does what you intended.

## Fast by design. Measured against Rust.

**Fast to iterate. Fast to run.** Debug builds use Cranelift for fast edit–build–run feedback. Optimized builds lower directly to LLVM IR for LLVM optimization and native code generation on supported platforms. [Build modes and toolchain](documentation/contributing/rust-toolchain.md).

**No tracing GC. Ownership lets the compiler release plain data at its last safe use.** Resources, closures and handles retain their scoped lifetimes. Generics specialize to concrete types, short strings can live inline, and borrowing lets programs read data without paying for a copy.

The same function model covers sequential and concurrent work. Cooperative tasks overlap I/O; workers spread CPU work across cores; process groups provide a separate process boundary. There is no `async`/`await` split to carry through the call graph. [Concurrency and its guarantees](documentation/core-language/concurrency/_index.md).

Across the published October 25 [kernels](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25), [competence tests](bench/perf/competence/README.md#latest-2026-10-25) and [operation benchmarks](bench/perf/programs/results.md#main-at-c1b81215-2026-10-25), comparable timed cases span **0.38–3.99× Rust's execution time** at revision `c1b81215` (`opt-level=3`), excluding loops optimized away. Lower is faster. Wins in maps and sorting sit alongside slower string appends. The linked results include the full tables, overflow-checked Rust comparisons and methodology.

## Code you can actually review

Familiar, consistent syntax keeps the program's decisions visible. Imports expose dependencies; signatures state contracts. Mutation, error propagation and resource cleanup appear alongside the work they affect, so reviewers can follow both the normal path and its boundaries.

Review tools build on that source. [`ms review --diff`](documentation/developer-tooling/implementation.md#review-report) compares checked versions and reports changes to contracts, error flow and resource scopes. It gives you concrete places to look while the code and tests explain what the change does.

## Built with agents. Improved through evidence.

We use coding agents to build Manuscript itself. The compiler is written in Rust; standard-library declarations and many implementations are written in Manuscript. Shared [repository skills](skills/README.md), [recorded lessons](.experts/README.md) and [development checks](documentation/contributing/development.md) carry what we learn into the next change.

We study where agents struggle: misunderstood APIs, failed builds, repair attempts and unnecessary context. The [agent benchmark](bench/agent/README.md) uses fresh workspaces and hidden tests, recording success, build attempts, tokens and cost. [Published results](bench/agent/results/summary-2026-10-22.md) include failures and reruns. Those coding evaluations guide the language and tools; the native benchmarks measure execution speed separately.

## Try it on one real task

[Get the compiler](documentation/learn/getting-started.md), then give your agent a small CLI you actually need. Have it look up APIs, write tests and work through the compiler's feedback.

Save this example as `config.ms`: JSON is parsed into a declared type, a parse error propagates to the caller, and an unset port gets a default.

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

Run `ms test config.ms` to check the example: `1 tests, 0 failed`. Use `ms init my-app` to start a project, then follow the [quickstart](documentation/learn/getting-started.md) through running, testing and building a native executable.

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) · [Project vision](VISION.md)
