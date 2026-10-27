# Manuscript

**The language for the agentic era.**

Manuscript is a statically typed, natively compiled language for a loop where agents write the code and people review and run it. It reads like Python, compiles to one static executable, has no garbage collector and no `async`, and ships a toolchain that answers an agent's questions in a few hundred tokens.

[Try Manuscript](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [Performance results](bench/perf/README.md)

*Alpha: syntax and APIs can change. The examples below follow current source and were checked with `ms` built from this tree; releases may lag. The first native build downloads pinned tools. [Setup and platform requirements](documentation/learn/getting-started.md).*

## What is different

Most languages were designed for people typing. Manuscript's choices follow from a different question: what does an agent need to produce a correct program on the first or second try, and what does a reviewer need to trust it?

### The compiler is written for the agent reading it

Every diagnostic reads `cause; fix`. When an agent writes a habit from another language, the message names the Manuscript spelling instead of a bare syntax error:

```manuscript
def count(xs: List[Int]) -> Int:
    return len(xs)
```

```text
count.ms:2:12: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
```

When the repair is mechanical, the JSON diagnostic carries a byte-exact edit and `ms check --fix` applies it. A discarded `Result` is an error, not a warning, and the message says what to write (`try ...`, or `.get()`). Runtime faults from `ms run --json` and `ms test --json` arrive as data: a kind, a message with the offending values, a position, a trace, and whether cleanup ran.

Three commands cover what a model would otherwise guess at. `ms guide` prints the whole language in about 4 KB, with common mistakes beside their fixes. `ms search_symbol <words>` finds project and standard-library APIs with bounded output. `ms verify` folds check, format, lint and test into one exit status and one JSON document. [Commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents) · [Diagnostics](documentation/developer-tooling/source/diagnostics.md)

### Ownership without lifetimes, borrows without annotations

Records, lists, maps and strings are values with one owner. The compiler moves them at their last use, borrows them for reads and drops them deterministically. There is no tracing collector and no reference counting on ordinary data.

Borrowing is inferred from the binding: `let x = a.b` is a shared borrow, `var x = a.b` an exclusive one. The only marker in the language is `ref` on a function that lends part of its argument back, written once in the signature and never at the call site:

```manuscript
type Box:
    items: List[Int]

impl Box:
    def list() -> ref List[Int]:
        return self.items

def grow(var b: Box) -> Int:
    var xs = b.list()
    xs.append(1)
    return b.items.length()
```

`var` marks mutation at the declaration and at the call. `.clone()` marks every deep copy. `Shared[T]` is the explicit, reference-counted exception, and a lock on it is a `with` block the compiler can see. [Mutation and references](documentation/core-language/types/references.md) · [Ownership rules](crates/ms-check/OWNERSHIP.md)

### Faults the checker finds before the program runs

Beyond types, `ms check` rejects a specific list of mistakes that other compiled languages leave to runtime or to a linter:

- A `Result` that is dropped on the floor.
- A `match` with a missing case.
- A value of a type that implements `Closeable`, bound and then neither closed, returned nor passed on.
- Integer arithmetic over literals that overflows, divides by a constant zero, or indexes outside a list literal.
- A `lock` of a `Shared` value inside a `with` block that already holds it.
- A `Shared` value inside a worker or process message, which would silently copy it.

The resource check covers explicit `Closeable` implementations, not every standard handle. What the checker cannot prove, the runtime catches as a fault with a source trace: overflow, bounds, deadlock between tasks or workers, and a cleanup that did not run. [Faults](documentation/core-language/errors/faults.md) · [Cleanup](documentation/core-language/cleanup/_index.md)

### Concurrency without `async`, isolation by construction

Any function can wait, so there is no `async`, no `await` and no function coloring. Three groups cover the three places work can run, and all three own their work inside a `with` block and cancel what is still running when the block ends:

| Group | Runs | Shares |
| --- | --- | --- |
| `TaskGroup` | cooperative tasks on one thread | values, moved through typed channels |
| `WorkerGroup` | isolated OS threads, each with its own memory and scheduler | JSON messages only |
| `ProcessGroup` | child processes | JSON messages and standard streams |

A worker entry is a named top-level function that takes no arguments: there is nothing to capture, so there is no shared state to race on. Eight CPU-bound jobs scale 3.95× from one to four workers in the [recorded run](bench/perf/workers/README.md). When every task and worker is waiting on another, the program stops with a deadlock fault instead of hanging. [Concurrency](documentation/core-language/concurrency/_index.md)

### Testing, property testing and fuzzing in the language

A `test "name":` block runs under `ms test`; a tests file needs no `main`. `check` from `@std/test/property.ms` runs a property over generated inputs, shrinks a failure to a small counterexample and prints the seed to replay it:

```manuscript
from "@std/test/property.ms" import check, ints, lists
from "@std/test.ms" import expect_equal

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), lambda xs: expect_equal(xs.reversed().reversed(), xs))
```

`ms test --fuzz 30s` turns the same property into a time-boxed fuzzer; each case runs in a forked child, so a fault that kills the process is still reported and replayable with `--seed`. [Testing](documentation/learn/testing.md)

### A standard library written in Manuscript

The standard library is about 14,000 lines of Manuscript across more than 40 modules, with Rust limited to small primitives. It covers files, streams, processes, TCP, an HTTP client and server with routing and server-sent events, JSON, TOML, YAML, CSV, crypto, archives, decimals, semver, time, logging and command-line parsing. Because the library is Manuscript, `ms search_symbol` shows the same source an agent would write, and an agent can read it. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)

### Review tools derived from the source, not from a model

`ms review --diff` compares the checked program before and after a change and reports changed contracts, error flow, effects and `with` scopes, ranked by where a reader should look first. `ms diagram` draws call and flow graphs from the same analysis. Equal inputs print equal bytes, so the evidence a reviewer gets about an agent's change does not come from asking another model. [Review report](documentation/developer-tooling/implementation.md#review-report)

## Native speed, measured against Go and Rust

Debug builds go through Cranelift for fast edit-build-run turnaround; Release builds lower to LLVM IR. On the recorded October 25 run (`c1b81215`, linux/amd64, four cores), Manuscript was faster than hand-written Go on all seven whole-program kernels. Against Rust at `opt-level=3`, the same revision spans **0.38× to 3.99× Rust's time** across 26 comparable kernel, competence and operation cases:

| Case | Manuscript | Rust | ms / Rust |
| --- | ---: | ---: | ---: |
| Binary trees | 26.1 ms | 30.0 ms | 0.87× |
| Int map counting | 14.4 ms | 23.8 ms | 0.61× |
| String-keyed map, 10M | 103.2 ms | 206.5 ms | 0.50× |
| Sort 1M | 23.5 ms | 33.1 ms | 0.71× |
| n-body | 8.2 ms | 6.7 ms | 1.22× |
| String append, per op | 5.12 ns | 1.28 ns | 3.99× |

Manuscript checks integer overflow and list bounds everywhere; the linked pages add an overflow-checked Rust column, the full tables and reproduction commands. [Kernels](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25) · [Competence](bench/perf/competence/README.md#latest-2026-10-25) · [Operations](bench/perf/programs/results.md#main-at-c1b81215-2026-10-25) · [JSON vs V8](bench/perf/json/results.md) · [HTTP vs Go](bench/perf/web/results.md)

## One toolchain, three platforms

`ms` checks, formats, lints, tests, builds, profiles and serves the language server. Release archives are built natively for Linux, macOS and Windows on amd64 and arm64, and CI runs the conformance corpus on all three operating systems. Linux executables are static musl binaries; macOS needs no SDK to link; Windows needs no MSVC to link programs. [Toolchain](documentation/contributing/rust-toolchain.md)

## Built with agents, measured against agents

We build Manuscript with coding agents, guided by shared [repository skills](skills/README.md) and [recorded lessons](.experts/README.md). The compiler is Rust; the standard library and its documentation are Manuscript.

The [agent benchmark](bench/agent/README.md) gives the same challenges to a coding agent in Manuscript, TypeScript, Go and Rust with hidden tests, and records pass rate, first-build success, tokens and cost. The [October 22 run](bench/agent/results/summary-2026-10-22.md) passed 10 of 10 small challenges in Manuscript with one trial each; first-build success (1 of 10) and source size (about 1.3× TypeScript) are published alongside, because they are the numbers we are working on. These evaluations are kept separate from the execution-speed benchmarks above.

## Try it on one real task

[Get the compiler](documentation/learn/getting-started.md), then give your agent a small CLI you actually need. Have it run `ms guide`, look up APIs with `ms search_symbol`, write tests and work through the compiler's feedback.

Save this as `config.ms`: JSON is parsed into a declared type, a parse error propagates to the caller, and an unset port gets a default.

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

```sh
ms test config.ms
```

```text
RUN config.ms::an unset port uses the default
PASS config.ms::an unset port uses the default
1 tests, 0 failed
```

Then `ms init my-app`, and follow the [quickstart](documentation/learn/getting-started.md) through `ms verify` and `ms build` to a native executable.

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) · [Project vision](VISION.md)
