# Manuscript

**The language for the agentic era.**

Manuscript is a ground-up attempt to build the ideal language for agentic development.

When agents write software, the language shapes how much context they need, how reliably they can make a change, and how well people can understand the result. Manuscript designs for that whole relationship: token-efficient code that stays readable, a small and regular language that is easy to reason about, and compiler-backed tools that make programs inspectable.

We learn by watching agents build real programs. Their mistakes, repair attempts, token use, and test results feed back into the syntax, standard library, diagnostics, and tools. The ambition is to make every part of the language serve agent generation, human understanding, and precise analysis together.

[Get started](documentation/learn/getting-started.md) · [Language tour](documentation/learn/tour.md) · [The book](https://manuscript-lang.github.io/manuscript/) · [Release archives](https://github.com/manuscript-lang/manuscript/releases)

## Designed around how agents work

- **Learn from behavior.** The [agent benchmark](bench/agent/README.md) records test outcomes, tokens, turns, time, and cost. We use those observations to find friction and improve the language itself, from common syntax mistakes to the feedback that helps an agent recover.
- **Spend tokens on meaning.** Compact expressions, inferred types, pipe flows, and a concise API vocabulary aim to reduce the context needed to express and understand a program. Token efficiency is a design goal alongside readability and analyzability; shorter code still needs to say clearly what it does.
- **Keep reasoning local.** A small, regular core, explicit types at boundaries, `Optional` and `Result`, and visible mutation make intent easier to follow. Python-like syntax gives agents a familiar starting point, paired with Manuscript’s own static checking, ownership and borrowing, and native compilation. Familiarity guides the design; Python compatibility is not the goal.
- **Make analysis part of the language.** Static checking, structured diagnostics, symbol search, inspection, and diagrams derive evidence from source. Agents can find exact APIs and act on compiler feedback; people can examine the same program and its relationships.
- **Design the whole loop.** The compiler, standard library, formatter, tests, language server, and profiler belong to one toolchain. Native executables, explicit numeric widths, and scoped tasks, workers, and processes give that philosophy practical reach.

The [vision](VISION.md) sets out the longer-term ambition. The [language tour](documentation/learn/tour.md) shows how these choices feel in code.

Manuscript is in alpha. Syntax, APIs, and platform behavior can change. These repository docs describe current `main`; a published release may lag it. Consult the documentation in the release's source tag or [build this checkout](#build-from-source) to try the latest features.

## Try it

To try the current implementation, [build from source](#build-from-source) and use `target/release/ms` for the commands below. If the [releases page](https://github.com/manuscript-lang/manuscript/releases) provides an archive for your platform, you can instead extract it and run from that directory:

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

On Windows PowerShell, use `.\ms.exe`. The example prints:

```text
Arguments: 2
```

The first native link downloads a pinned, checksum-verified linker into the cache. Release builds also fetch LLVM tools when needed; later builds reuse them. Plan for network access on first use, or configure local tools as described in [how it works](documentation/developer-tooling/how-it-works.md). The compiler distribution is not a fully offline toolchain.

`check` validates source without running it; `run` builds a temporary executable and forwards arguments after `--`. Keep an executable and run the example's test with:

```sh
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

The resulting executable runs without `ms` installed. Follow [your first program](documentation/learn/getting-started.md) to edit the example, run it again, and create a project.

## Typed data, explicit errors

Put `ms` on your `PATH` for the following commands (or use its full path). Save this as `orders.ms`, then run `ms test orders.ms`. It parses JSON directly into your types and checks both the successful result and malformed input:

```manuscript
from "@std/json.ms" import parse
from "@std/testing.ms" import expect_equal

type Order:
    customer: String
    cents: Int
    coupon: Optional[String]

def discount(order: Order) -> Int:
    if let code = order.coupon:
        return order.cents / 10 if code == "SAVE10" else 0
    return 0

def summary(text: String) -> Result[String, Error]:
    let orders = try parse[List[Order]](text)
    var total = 0
    for order in orders:
        total += order.cents - discount(order)
    return ok(f"{orders.length()} orders, {total / 100} dollars")

test "orders from JSON":
    let text = (
        "[{\"customer\":\"Sam\",\"cents\":5000,\"coupon\":\"SAVE10\"},"
        + "{\"customer\":\"Ana\",\"cents\":2500}]"
    )
    try expect_equal(try summary(text), "2 orders, 70 dollars")
    try expect_equal(summary("not json").is_error(), True)
```

`try` passes a failure to the caller. `Optional[String]` represents a coupon that may be absent; `if let` gives its value when present. The standard library includes JSON, files, streams, HTTP, networking, text, time, and processes. Find the exact API with `ms search_symbol json.parse` or the [library reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/).

## Small building blocks

Functions use `def name(...) -> Type`; function types use `Callable`, and callbacks use `lambda`. A pipe feeds its value into the next call. This complete example combines filtering, mapping, and a test:

```manuscript
from "@std/testing.ms" import expect_equal

def positive(values: List[Int]) -> List[Int]:
    return values.filter(lambda (value: Int) -> Bool: return value > 0)

def doubled(values: List[Int]) -> List[Int]:
    return values.map(lambda (value: Int) -> Int: return value * 2)

test "pipe flow":
    let result = [-2, 0, 3, 5] | positive | doubled
    try expect_equal(result, [6, 10])
```

Save it as `flow.ms` and run `ms test flow.ms`. The [tour](documentation/learn/tour.md) builds from variables and functions through types, errors, modules, and cleanup.

Ownership and borrowing are central to the memory model. Ordinary records and collections have value semantics: the compiler borrows or moves them according to use, `var` makes mutation visible, and `.clone()` explicitly copies ordinary nested data. Owned values are reclaimed deterministically during normal execution, without a tracing garbage collector. External resources still need `with` or `close()`, and shared handles have their own contracts. See [references and borrowing](documentation/core-language/types/references.md) and [scoped cancellation](documentation/core-language/concurrency/task-groups.md) for the exact rules.

`Int` remains signed 64-bit and `Float` remains 64-bit. Sized integer and floating-point types let you choose storage and arithmetic deliberately; conversions make width changes explicit. Exclusive `a..b` ranges include `a` and stop before `b`. See [numeric types](documentation/core-language/basics/numbers-and-booleans.md).

## Concurrency with a scope

Use a group inside `with` so the work has an explicit lifetime:

| Choose | For | Communication |
| --- | --- | --- |
| `TaskGroup` | Cooperative work on one runtime thread; a CPU-bound task does not provide parallelism | A callback receives a typed channel; task values move through it |
| `WorkerGroup` | Parallel work on isolated OS threads | A named zero-argument `Unit` entry opens `worker_channel`; messages are serialized |
| `ProcessGroup` | Running a named entry in a fresh child process | Typed messages or piped stdin, stdout, and stderr |

`Channel[In, Out]` sends `In` and receives `Out`; its `Transport` supplies the operations. These are distinct execution models, not interchangeable ways to share mutable objects. Read [concurrency](documentation/core-language/concurrency/_index.md) for runnable examples, channels, and scoped cancellation. Isolation here is an execution model, not a security sandbox.

## Tools for agents and people

After putting `ms` on your `PATH`, use these commands in a project:

```sh
ms guide
ms search_symbol "read file"
ms check ms.toml --json
ms verify ms.toml
```

`ms guide` is a compact language reference; `search_symbol` finds project and standard-library APIs. Diagnostics name the cause and a concrete fix. `ms check --fix` applies supported mechanical repairs. `ms verify` combines checking, formatting checks, linting, and tests; it does not establish that a program is correct or secure.

The [tooling guide](documentation/developer-tooling/implementation.md) covers structured output, inspection, diagrams, and profiling. The [VS Code extension](extensions/vscode/README.md) adds editor diagnostics and navigation into the standard declarations.

## Native code, measured performance

`ms` checks and lowers your source to an intermediate representation, then compiles it ahead of time to native machine code and links it with the runtime and standard library. There is no JIT compilation at runtime. Cranelift keeps debug builds fast for quick iteration. Release and MinSizeRel builds use LLVM to optimize for runtime performance or binary size when its tools are available, falling back to Cranelift if they cannot be fetched. The resulting executable runs without `ms` installed. See [how compilation works](documentation/developer-tooling/how-it-works.md).

Performance is part of the design: native execution, explicit numeric widths, packed storage, and compiler optimizations aim to make readable code efficient to run. Benchmark results guide that work alongside the agent feedback loop.

The project uses [agent exercises](bench/agent/README.md) to study how agents build programs, and [performance benchmarks](bench/perf/README.md) to guide compiler and runtime work. Results depend on the program, revision, build mode, hardware, and comparison settings. The benchmark directories include sources, commands, and recorded results; measure your own workload before drawing conclusions about performance.

## Build from source

Install [rustup](https://rustup.rs), Make, and a C compiler, then run from this checkout:

```sh
make build
target/release/ms run examples/hello/ms.toml -- first second
```

`make build` builds the native runtime before embedding it in `ms`. The repository pins Rust in `rust-toolchain.toml`. See the [Rust toolchain guide](documentation/contributing/rust-toolchain.md) for downloads, platform prerequisites, and checks.

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn by running code | [Your first program](documentation/learn/getting-started.md), then the [tour](documentation/learn/tour.md) |
| Build a useful script or service | [Common tasks](documentation/learn/common-tasks.md) |
| Look up an exact rule | [Core language](documentation/core-language/_index.md) |
| Find a standard type or function | `ms search_symbol <name or words>` and the [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) |
| Choose build and profiling settings | [Build levels](documentation/developer-tooling/builds/build-levels.md) and [tooling](documentation/developer-tooling/implementation.md) |
| Contribute | [Architecture](documentation/contributing/architecture.md), [development checks](documentation/contributing/development.md), and [maintenance](documentation/contributing/maintenance.md) |

Source lives in `crates/`, authored guides in `documentation/`, and standard declarations and library guides in `stdlib/`. The repository-backed website builds into ignored `.artifacts/book/`.
