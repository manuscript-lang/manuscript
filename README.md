# Manuscript

**The language for the agentic era.**

Manuscript starts from one premise: agents will write most of the code, and people have to understand, check and run it. An agent has a limited context, cannot hold a whole program in its head, and learns from the compiler one round trip at a time. Every design choice below exists because of that.

[Try Manuscript](documentation/learn/getting-started.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [Language tour](documentation/learn/tour.md) · [Performance](bench/perf/README.md)

## Each round trip costs context, so the compiler names the repair

An agent that gets "syntax error" guesses. One that gets the fix types it. Every Manuscript diagnostic reads `cause; fix`, and a habit from another language is answered with the Manuscript spelling:

```manuscript
def count(xs: List[Int]) -> Int:
    return len(xs)
```

```text
count.ms:2:12: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length()
```

When the repair is mechanical the diagnostic carries the exact edit and `ms check --fix` applies it, so the round trip is zero. A runtime fault comes back from `ms test --json` as data with kind, values, position and trace. The agent does not need the manual in its context: `ms guide` is the whole language in 4 KB, `ms search_symbol` answers one API question in bounded output, and `ms verify` is check, format, lint and test in one exit code. [Commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents)

## Memory is decided by the compiler, so the agent cannot get it wrong

Lifetimes are a whole-program fact, and an agent working from a window of a file cannot track them. A collector hides the cost and makes a binary carry a runtime. Manuscript takes the third path: one owner per value, moved at its last use, dropped deterministically, with borrows inferred from how a value is bound. `let x = a.b` borrows. `var x = a.b` borrows exclusively. The only marker is `ref`, written once on a function that lends part of its argument and never at a call site:

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

Every place the agent mutates (`var`) or copies (`.clone()`) is visible in the source, so a reviewer sees what a generated change does to data without reading the callee. [References](documentation/core-language/types/references.md)

## Mistakes an agent makes often are compile errors, not runtime surprises

A dropped error, a forgotten case and an unclosed handle are the mistakes a model makes when it is confident. Finding them in production costs a debugging session; finding them at `ms check` costs one message. So these are errors:

- A `Result` silently dropped.
- A `match` missing a case.
- A `Closeable` opened and never closed, returned or passed on (user types today; [#1590](https://github.com/manuscript-lang/manuscript/issues/1590) widens it).
- Literal arithmetic that overflows or divides by zero. A literal index outside a list literal.

Everything the checker cannot prove, the runtime catches as a fault with a source trace: overflow, bounds, deadlock, a cleanup that did not run. [Faults](documentation/core-language/errors/faults.md)

## One function model, because `async` doubles the surface an agent has to learn

Function coloring means two of every API and a leaf change that rewrites every caller. In Manuscript any function can wait, so a change stays where it was made. Concurrent work lives inside a `with` block that owns it and cancels whatever is still running when the block ends, which means a generated program cannot leak a task the agent forgot to join:

| Group | Runs on | Shares |
| --- | --- | --- |
| `TaskGroup` | one thread, cooperatively | values over typed channels |
| `WorkerGroup` | OS threads, separate memory | JSON messages only |
| `ProcessGroup` | child processes | JSON messages, standard streams |

A worker's entry is a named top-level function with no arguments. There is nothing to capture, so there is no data race for the agent to introduce. Eight CPU jobs scale 3.95× on four workers in the [recorded run](bench/perf/workers/README.md). Mutual waiting is a deadlock fault, not a hang. [Concurrency](documentation/core-language/concurrency/_index.md)

## Generated inputs, because an agent's tests share its blind spots

A model writes tests that encode the same assumptions as its code. Property tests draw inputs the agent did not think of, and shrink a failure to the smallest case that still fails:

```manuscript
from "@std/test/property.ms" import check, ints, lists
from "@std/test.ms" import expect_equal

test "reversing twice restores a list":
    try check("reverse twice", lists(ints(-100, 100)), lambda xs: expect_equal(xs.reversed().reversed(), xs))
```

A failure prints a counterexample and the seed to replay it. `ms test --fuzz 30s` turns the same test into a fuzzer, each case in a forked child so a crash is still reported. [Testing](documentation/learn/testing.md)

## The standard library is Manuscript, so there is one language to learn

An agent that reads a library implemented in another language learns nothing it can reuse. Manuscript's library is about 14,000 lines of Manuscript across more than 40 modules, with Rust only for small primitives: HTTP server and client with routing and server-sent events, TCP, processes, files, streams, JSON, TOML, YAML, CSV, crypto, archives, decimals, semver, time, logging, CLI parsing. What the agent reads is what it would write, and what it would write can become part of the library. [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/)

## Review evidence has to come from somewhere other than the generator

If a model wrote the change, asking a model to summarize it is not a check. `ms review --diff` compares the checked program before and after and ranks changed contracts, error flow and `with` scopes by where a reader should look first. `ms diagram` draws call and flow graphs from the same analysis. Same input, same bytes, every time. [Review report](documentation/developer-tooling/implementation.md#review-report)

## Ordinary code has to be fast, because agents write ordinary code

An agent writes the straightforward loop, not the clever one, so the compiler has to make the straightforward loop fast. Debug builds go through Cranelift for a fast edit-check-run loop; release builds go through LLVM. On the October 25 run (`c1b81215`, linux/amd64), Manuscript beat hand-written Go on all seven kernels. Against Rust at `opt-level=3` with overflow checks on, the configuration that matches Manuscript's checked arithmetic, 28 comparable cases span **0.42× to 4.51× Rust's time**:

| Case | Manuscript | Rust | ms / Rust |
| --- | ---: | ---: | ---: |
| Binary trees | 26.1 ms | 33.6 ms | 0.78× |
| String-keyed map, 10M | 103.2 ms | 207.8 ms | 0.50× |
| Sort 1M | 23.5 ms | 34.1 ms | 0.69× |
| n-body | 8.2 ms | 6.7 ms | 1.23× |
| String append, per op | 5.12 ns | 1.14 ns | 4.51× |

The linked pages add the unchecked Rust column, Go, and reproduction commands. [Kernels](bench/perf/kernels/README.md#main-at-c1b81215-2026-10-25) · [Competence](bench/perf/competence/README.md#latest-2026-10-25) · [Operations](bench/perf/programs/results.md#main-at-c1b81215-2026-10-25) · [HTTP vs Go](bench/perf/web/results.md)

Library results from the October 27 runs (linux/amd64, 4 shared cores; compare only within one page):

- **HTTP server:** at parity with hyper on two workers. `/health` 113k–119k req/s against 114k–119k, p99 2.2 ms against 1.9–2.7 ms, and 62 MB against 104 MB resident with 10,000 idle connections. [Web results](bench/perf/web/results.md#2026-10-27-rust-baseline-equal-cores)
- **CSV:** `parse` on plain input takes 476–535 µs against the Rust `csv` crate's 974–1212 µs, about 2× faster. On quoted input it takes 785–832 µs against 804–911 µs, within run-to-run noise. [CSV](bench/perf/csv/README.md)
- **JSON:** parsing `twitter.json` into a tree runs at 451 MB/s against `serde_json::Value` at 137 MB/s, about 3×. [JSON](bench/perf/json/results.md#2026-10-27-against-serde_json-and-the-writer)

Native release builds for Linux, macOS and Windows, amd64 and arm64. The conformance corpus runs on all three in CI.

## The language is built the way it will be used

We build Manuscript with coding agents, and we measure them. The [agent benchmark](bench/agent/README.md) gives the same challenges to an agent in Manuscript, TypeScript, Go and Rust with hidden tests. The [October 22 run](bench/agent/results/summary-2026-10-22.md) passed 10 of 10 small challenges. First-build success (1 of 10) and source size (1.3× TypeScript) are published too, because every friction point there becomes a diagnostic, an API or a rule above.

*Alpha. Syntax and APIs can change. Every example here was run with `ms` built from this tree. [Setup](documentation/learn/getting-started.md).*

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
