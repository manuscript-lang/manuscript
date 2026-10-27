# Manuscript

**The language for the agentic era.**

Python's surface. Rust's ownership without the lifetimes. Go's concurrency without the goroutine leaks. One static binary, no garbage collector, no `async`, and a compiler that tells the agent what to type next.

[Try Manuscript](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [Performance](bench/perf/README.md)

*Alpha. Syntax and APIs can change. Every example here was run with `ms` built from this tree. [Setup](documentation/learn/getting-started.md).*

## The compiler talks to the agent, not past it

Other compilers report errors. Manuscript's names the fix. Write a habit from another language and the message spells the Manuscript one:

```manuscript
def count(xs: List[Int]) -> Int:
    return len(xs)
```

```text
count.ms:2:12: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
```

When the repair is mechanical, the diagnostic carries the exact edit and `ms check --fix` applies it. A runtime fault comes back from `ms test --json` as data, with kind, values, position and trace, not as stderr to scrape. `ms guide` is the whole language in 4 KB. `ms search_symbol` finds any API in bounded output. `ms verify` is check, format, lint and test in one exit code. [Commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents)

## Ownership you never annotate

Rust asks for lifetimes. Go and Python hand you a collector. Manuscript does neither: one owner per value, moved at its last use, dropped deterministically, and borrows inferred from how you bind. `let x = a.b` borrows. `var x = a.b` borrows exclusively. The single marker is `ref`, written once on a function that lends, never at a call site:

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

`var` marks mutation. `.clone()` marks a copy. `Shared[T]` is the one explicit way to share, and its lock is a `with` block the compiler can see. [References](documentation/core-language/types/references.md)

## Mistakes that do not reach production

These are compile errors in Manuscript. In most languages they are a code review, a linter, or a 3 a.m. page:

- A `Result` silently dropped.
- A `match` missing a case.
- A `Closeable` opened and never closed, returned or passed on (user types today; [#1590](https://github.com/manuscript-lang/manuscript/issues/1590) widens it).
- Literal arithmetic that overflows or divides by zero. A literal index outside a list literal.
- Locking a `Shared` you already hold. Sending a `Shared` to a worker.

Everything the checker cannot prove, the runtime catches as a fault with a source trace: overflow, bounds, deadlock, a cleanup that did not run. [Faults](documentation/core-language/errors/faults.md)

## Concurrency with no `async` and no leaks

Any function can wait. Nothing is colored. Work lives inside a `with` block that owns it and cancels whatever is still running when the block ends:

| Group | Runs on | Shares |
| --- | --- | --- |
| `TaskGroup` | one thread, cooperatively | values over typed channels |
| `WorkerGroup` | OS threads, separate memory | JSON messages only |
| `ProcessGroup` | child processes | JSON messages, standard streams |

A worker's entry is a named top-level function with no arguments. There is nothing to capture, so there is no data race to find. Eight CPU jobs scale 3.95× on four workers in the [recorded run](bench/perf/workers/README.md). Mutual waiting is a deadlock fault, not a hang. [Concurrency](documentation/core-language/concurrency/_index.md)

## Fuzzing is a flag, not a framework

```manuscript
from "@std/test/property.ms" import check, ints, lists
from "@std/test.ms" import expect_equal

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), lambda xs: expect_equal(xs.reversed().reversed(), xs))
```

A failing property shrinks to a small counterexample and prints the seed to replay it. `ms test --fuzz 30s` turns the same test into a fuzzer, each case in a forked child so a crash is still reported. [Testing](documentation/learn/testing.md)

## A standard library the agent can read

About 14,000 lines of Manuscript across more than 40 modules, Rust only for small primitives. HTTP server and client with routing and server-sent events, TCP, processes, files, streams, JSON, TOML, YAML, CSV, crypto, archives, decimals, semver, time, logging, CLI parsing. It is written in the language the agent writes, so what the agent reads is what it would write. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)

## Review evidence that is not another LLM

`ms review --diff` compares the checked program before and after a change and ranks changed contracts, error flow and `with` scopes by where to look first. `ms diagram` draws call and flow graphs. Same input, same bytes, every time. [Review report](documentation/developer-tooling/implementation.md#review-report)

## Faster than Go. Trading blows with Rust.

Cranelift for debug builds, LLVM for release. On the October 25 run (`c1b81215`, linux/amd64), Manuscript beat hand-written Go on all seven kernels. Against Rust at `opt-level=3`, 26 comparable cases span **0.38× to 3.99× Rust's time**:

| Case | Manuscript | Rust | ms / Rust |
| --- | ---: | ---: | ---: |
| Binary trees | 26.1 ms | 30.0 ms | 0.87× |
| String-keyed map, 10M | 103.2 ms | 206.5 ms | 0.50× |
| Sort 1M | 23.5 ms | 33.1 ms | 0.71× |
| n-body | 8.2 ms | 6.7 ms | 1.22× |
| String append, per op | 5.12 ns | 1.28 ns | 3.99× |

Manuscript checks overflow and bounds on every operation; the linked pages add an overflow-checked Rust column and reproduction commands. [Kernels](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25) · [Competence](bench/perf/competence/README.md#latest-2026-10-25) · [Operations](bench/perf/programs/results.md#main-at-c1b81215-2026-10-25) · [HTTP vs Go](bench/perf/web/results.md)

Native release builds for Linux, macOS and Windows, amd64 and arm64. The conformance corpus runs on all three in CI.

## Built by agents. Scored by agents.

We build Manuscript with coding agents. The [agent benchmark](bench/agent/README.md) gives the same challenges to an agent in Manuscript, TypeScript, Go and Rust with hidden tests. The [October 22 run](bench/agent/results/summary-2026-10-22.md) passed 10 of 10 small challenges. First-build success (1 of 10) and source size (1.3× TypeScript) are published too, because those are the numbers we are chasing.

## Try it

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

Then hand your agent a small CLI you actually need and watch it work through `ms guide`, `ms search_symbol` and the compiler's feedback.

[Language tour](documentation/learn/tour.md) · [Task recipes](documentation/learn/common-tasks.md) · [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) · [Vision](VISION.md)
