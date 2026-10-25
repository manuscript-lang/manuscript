# Manuscript

**The language for the agentic era.**

Manuscript is a statically typed, natively compiled language built from the ground up for a world where agents write most of the code and people have to understand it. It reads like Python, compiles to a single native executable, manages memory by ownership instead of a garbage collector, runs concurrent work without `async`, and ships a standard library broad enough to build complete services. Every design decision is tested against what coding agents actually do with it, and every performance claim below comes with the command that reproduces it.

[Get started](documentation/learn/getting-started.md) · [Language tour](documentation/learn/tour.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [The book](https://manuscript-lang.github.io/manuscript/) · [Releases](https://github.com/manuscript-lang/manuscript/releases)

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

Save it as `orders.ms` and run `ms test orders.ms`. JSON decodes straight into your record type, `Optional` says a coupon may be absent, `try` hands a failure to the caller, and the test runs in the same file. Nothing here needs an import beyond the two shown.

Manuscript is in alpha: syntax, APIs and platform behavior can change, and these docs follow `main`.

## Why Manuscript

**Reads like Python, runs like native code.** `def`, four-space blocks, `lambda`, `for i in 0..n`, f-strings and `True`/`False` are what agents already write fluently. Underneath, the compiler infers types, checks ownership, monomorphizes generics and emits machine code through Cranelift (debug) or LLVM (release). On seven whole-program kernels Manuscript beats hand-written Go on every one and is level with Rust built with overflow checks on five ([numbers below](#measured-not-asserted)).

**Feedback an agent can act on.** Diagnostics are `<cause>; <fix>`. Habits from Python, TypeScript, Go and Rust get a named replacement instead of a parse error, mechanical repairs carry a byte-exact `fix` that `ms check --fix` applies, and a runtime fault is JSON with a kind, a position and a trace. See [written for agents](#written-for-agents).

**Concurrency without `async`.** Any function can wait. A `TaskGroup` runs cooperative tasks on one thread, a `WorkerGroup` runs isolated entries on OS threads, a `ProcessGroup` runs them in child processes, and all three talk over typed channels inside a `with` block that owns the work. Eight CPU-bound jobs over four workers run 3.95x faster than over one, and the runtime is hardened by adversarial reviews that probe for leaks, hangs and unsound sharing.

**Ownership you can follow, no garbage collector.** Values have one owner and are dropped at their last use. `var` marks mutation at the declaration and at the call (`reset(var counter)`), `.clone()` makes copies visible, and borrows are lexical with no lifetimes in source. An HTTP server holding 10,000 idle connections sits at 31 MB where Go's `net/http` uses 197 MB, and it answers `/health` at 76-82k requests per second against Go's 55k on the same machine.

**Batteries included.** Files, streams, processes, HTTP client and server, TCP, JSON (faster than V8 on every document we measured), JSON streaming, CSV, TOML, YAML, HTML, time, crypto, random, regex, logging, decimal, semver, archives, sized numerics (`Int8` to `Int64`, `Float32`), and a test runner, all in `ms`. Find any of it with `ms search_symbol <words>`.

**Measured, not asserted.** The [agent benchmark](bench/agent/README.md) gives the same twenty challenges to a coding agent in Manuscript, TypeScript, Go and Rust with hidden tests, and the [performance benchmarks](bench/perf/README.md) pin every speed claim to a script, a machine and a revision. Both are in this repository, including the results that are not flattering yet.

## Measured, not asserted

All runs below: `main` at `c1b81215` (2026-10-25) unless noted, Linux x86-64, four cores, Go 1.24.7, rustc 1.99.1, Node 22, `ms` Release build with LLVM. Ratios are Manuscript time over the other language's time, so below 1.00x Manuscript is faster. Compare only numbers from one machine; rerun before drawing conclusions about your workload.

### Whole-program kernels against Go and Rust

Ordinary programs written the way a user would write them, each compared with hand-written Go and Rust using a slice, struct or map directly; every sample must report the same checksum. "Rust, checked" is the same source with `-C overflow-checks=on`, which matches Manuscript's checked `Int` arithmetic. Median of 5, microseconds. Reproduce: `MS=./target/release/ms GO=go sh bench/perf/kernels/run.sh 5`; details in [`bench/perf/kernels`](bench/perf/kernels/README.md).

| kernel | Manuscript | Go | Rust | Rust, checked | ms / Go | ms / Rust | ms / Rust, checked |
|---|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 29,703 | 63,413 | 26,714 | 28,160 | 0.47x | 1.11x | 1.05x |
| nbody_200k | 8,216 | 9,836 | 6,716 | 6,686 | 0.84x | 1.22x | 1.23x |
| life_128x128_50 | 4,306 | 55,290 | 3,401 | 3,581 | 0.08x | 1.27x | 1.20x |
| matmul_200 | 8,040 | 11,670 | 6,990 | 7,707 | 0.69x | 1.15x | 1.04x |
| trees_d16_x20 | 26,065 | 42,206 | 29,972 | 33,569 | 0.62x | 0.87x | 0.78x |
| collatz_1M | 242,730 | 285,058 | 178,638 | 274,975 | 0.85x | 1.36x | 0.88x |
| map_count_2M | 14,428 | 25,054 | 23,757 | 24,993 | 0.58x | 0.61x | 0.58x |

### Agent-style workloads against Go and Rust

The reference solutions of the small agent challenges (CSV grouping, a calculator, ciphers, inventory, dynamic programming, BFS, cron, a log analyzer, a ledger, a diff) on about 3 MB of input each, outputs compared byte for byte. Best of 3, milliseconds. Reproduce: `MS=./target/release/ms sh bench/perf/workloads/run.sh 3`; details in [`bench/perf/workloads/results.md`](bench/perf/workloads/results.md).

| program | Manuscript | Go | Rust | ms / Go | ms / Rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 63 | 44 | 37 | 1.43x | 1.70x |
| c05-calculator | 46 | 48 | 98 | 0.96x | 0.47x |
| c09-ciphers | 63 | 61 | 33 | 1.03x | 1.91x |
| c13-inventory-orders | 118 | 248 | 143 | 0.48x | 0.83x |
| c14-dp-suite | 631 | 1,431 | 645 | 0.44x | 0.98x |
| c16-maze-bfs | 31 | 39 | 32 | 0.79x | 0.97x |
| c18-cron-next-runs | 809 | 1,052 | 807 | 0.77x | 1.00x |
| c25-log-analyzer | 28 | 60 | 21 | 0.47x | 1.33x |
| c36-bank-ledger | 97 | 109 | 63 | 0.89x | 1.54x |
| c44-unified-diff | 3 | 65 | 15 | 0.05x | 0.20x |

Faster than Go on 8 of 10 and level on the ciphers; the CSV grouping is the one program where Go is clearly ahead. Level with or ahead of Rust on 6 of 10. The four behind Rust are string-heavy, and the remaining costs (integer formatting in f-strings, scalar counting on short strings) are known and being worked on.

### JSON against Node (V8)

`@std/json` `parse` and `stringify` against `JSON.parse` and `JSON.stringify` on the standard documents. MB per second, median of at least five runs after warm-up. Reproduce: `sh bench/perf/json/run.sh`; details in [`bench/perf/json/results.md`](bench/perf/json/results.md).

| document | parse: Node | parse: Manuscript | speed | stringify: Node | stringify: Manuscript | speed |
|---|---:|---:|---:|---:|---:|---:|
| small RPC message | 190 | 230 | 1.21x | 299 | 352 | 1.18x |
| twitter.json | 569 | 770 | 1.35x | 364 | 1,266 | 3.48x |
| canada.json | 162 | 419 | 2.58x | 128 | 355 | 2.78x |
| citm_catalog.json | 671 | 904 | 1.35x | 908 | 1,269 | 1.40x |

### HTTP server against Go `net/http`

The same server on Manuscript's standard library and on Go, shared 4-CPU VM, server on 2 CPUs and load on the other 2, recorded at an earlier revision. Reproduce: `sh bench/perf/web/run.sh 5`; full table and the rows where Go is ahead in [`bench/perf/web/results.md`](bench/perf/web/results.md).

| measurement | Manuscript | Go |
|---|---:|---:|
| `/health` requests per second | 75.7k-81.9k | 54.8k-55.2k |
| `/health` p99 latency | 2.9-4.3 ms | 5.6-5.8 ms |
| threads | 2 | 67 |
| resident memory after load | 9.7 MB | 15 MB |
| resident memory with 10,000 idle connections | 31 MB | 197 MB |
| system calls in 5 idle seconds | 0 | 1 |

Where Manuscript is behind: file and DNS calls block the runtime thread, so an `/io` route and everything beside it waits on the disk.

### Agents writing Manuscript

The [agent benchmark](bench/agent/README.md) runs Claude Code on twenty challenges (ten small programs, ten applications of three to five thousand lines) with hidden tests, one trial per cell, and records pass rate, first-build success, turns, tokens and cost over passing runs only. Latest results ([2026-10-21](bench/agent/results/summary-2026-10-21.md), [2026-10-22](bench/agent/results/summary-2026-10-22.md), Claude Haiku):

| | Manuscript | TypeScript |
|---|---:|---:|
| small challenges passed | 10 / 10 | 10 / 10 |
| large applications passed | 8 / 10 | not run |
| first build succeeded (small) | 1-2 / 10 | 10 / 10 |
| source size, LLM tokens, same nine small challenges | 1.21-1.28x TypeScript | 1.00x |

Read it honestly: agents that have never seen the language now pass as often as they do in TypeScript, but they still need several compile-fix rounds to get there and write about 20-30% more source than they would in TypeScript. The first-build rate and the token ratio are the two numbers this project is trying to move, and the diagnostics below are how.

## Written for agents

Agents repeat the same mistakes across languages: they reach for `len`, `.unwrap()`, `camelCase` methods, `fn`, `async`, `except`. Manuscript answers each with the Manuscript spelling instead of a bare parse error:

```manuscript
def total(xs: List[Int]) -> Int:
    var sum = 0
    for i in 0..len(xs):
        sum += xs[i]
    return sum

def shout(name: String) -> String:
    return name.toUpperCase()
```

```text
habits.ms:3:17: resolution: unknown binding len; there is no len() function: call the length member, e.g. xs.length() (String also has byte_length and scalar_length)
habits.ms:8:17: resolution: unknown or ambiguous member toUpperCase on String; did you mean 'upper'?
2 errors; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)
```

When the repair is mechanical, the JSON diagnostic carries it and `ms check --fix` applies it:

```json
{"code": "MS2001", "message": "unknown binding duoble; did you mean 'double'?",
 "fix": {"position": {"line": 7, "column": 22}, "end": {"line": 7, "column": 28}, "replacement": "double"}}
```

A fault at runtime is data too. `ms run program.ms --json` on an out-of-range index exits 70 with a `fault` object: `"kind": "index_out_of_range"`, the message with its remedy (`pass a default: get(index:, default: ...)`), the position, the trace, and whether `with` cleanups ran.

The rest of the agent surface is four commands, chosen after an MCP server was tried and judged worse than a shell:

| Command | What it gives an agent |
| --- | --- |
| `ms guide` | The whole language cheat sheet, under 4 KB, with a program that checks |
| `ms search_symbol <words>` | Fuzzy lookup over the project and the standard library in under 100 ms; `<module>` or `<module>.<Name>` prints that page |
| `ms check --json`, `ms check --fix` | Structured diagnostics; mechanical repairs applied in place |
| `ms verify` | Check, format, lint and test in one exit status |

`ms test --json` and `ms run --json` report results and faults as versioned documents; `ms inspect`, `ms review` and `ms diagram` derive views of a program and of a change from source. See [commands for agents](documentation/developer-tooling/implementation.md#commands-for-agents) and the [diagnostics contract](documentation/developer-tooling/source/diagnostics.md).

## Concurrency with a scope

There is no `async`, no `await`, no function coloring. A group inside `with` owns the work it starts; leaving the block cancels what is still running and waits for it.

| Choose | For | Communication |
| --- | --- | --- |
| `TaskGroup` | Cooperative work that waits on I/O or messages, on one thread | A callable receives a typed `Channel`; values move through it |
| `WorkerGroup` | CPU-bound work on isolated OS threads | A named `def` opens `worker_channel()`; messages cross as JSON |
| `ProcessGroup` | The same entry in a fresh child process | Typed messages, or piped stdin, stdout and stderr |

```manuscript
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_ok

def square(n: Int) -> Int:
    return n * n

test "a group collects its results in start order":
    with TaskGroup[Int]() as group:
        for n in [1, 2, 3]:
            group.spawn(lambda ch: square(n))
        group.results() | try expect_ok | try expect_equal([1, 4, 9])
```

Tasks do not share mutable state: a captured value moves into the task, results come back through `result()` or the channel, and `Shared[T]` is the one explicit, reference-counted exception. Deadlocks are reported as a fault with both stacks, not a hang. Cancellation releases owned locals, closes sockets and kills children. Read [concurrency](documentation/core-language/concurrency/_index.md) for the rules; isolation is an execution model, not a security sandbox.

## Ownership and visible mutation

Records, lists, maps, strings and alternatives are values with one owner. The compiler moves them at their last use, borrows them for reads, and drops them deterministically; there is no tracing collector and no reference counting on ordinary data. Strings of 15 bytes or fewer never allocate, `a + b + c` fuses into one allocation, and `s = s + x` in a loop appends in place. `var` makes mutation visible at the declaration and at the call, `.clone()` makes copying visible, and `with` scopes external resources. The exact rules are in [references and borrowing](documentation/core-language/types/references.md) and the [design contract](crates/DESIGN.md).

## Try it

[Build from source](#build-from-source) and use `target/release/ms` for the commands below, or extract a [release archive](https://github.com/manuscript-lang/manuscript/releases) for your platform and run from that directory:

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
./ms build examples/hello/ms.toml -o hello
./ms test examples/hello/test.ms
```

On Windows PowerShell, use `.\ms.exe`. The example prints `Arguments: 2`, and the built executable runs without `ms` installed. The first native link downloads a pinned, checksum-verified linker into the cache; Release builds also fetch LLVM tools once. Plan for network access on first use, or configure local tools as described in [how it works](documentation/developer-tooling/how-it-works.md). Then follow [your first program](documentation/learn/getting-started.md) to edit the example and start a project with `ms init`.

## Build from source

Install [rustup](https://rustup.rs), Make and a C compiler, then run from this checkout:

```sh
make build
target/release/ms run examples/hello/ms.toml -- first second
```

`make build` builds the native runtime before embedding it in `ms`. The repository pins Rust in `rust-toolchain.toml`. See the [Rust toolchain guide](documentation/contributing/rust-toolchain.md) for platform prerequisites and checks.

## How it is built

Manuscript is implemented in Rust in [`crates/`](crates/DESIGN.md): `ms-syntax` parses, `ms-check` resolves, types and checks ownership, `ms-lower` and `ms-mir` produce and optimize an intermediate representation, `ms-clif` emits object code, and the embedded runtime and standard library link into a static executable. Standard declarations live in [`stdlib/*.ms`](stdlib/) and are the signature authority for both the compiler and the generated reference. Most of the standard library is written in Manuscript; Rust is reserved for small, general runtime primitives.

The project is also built mostly by coding agents: they file the issues, open the PRs, review each other, and CI merges on green. The repository remembers what they cannot: [AGENTS.md](AGENTS.md) routes to domain [skills](skills/), [`.experts/`](.experts/) records decisions and failure modes, and `make repo-check` enforces the rules that matter. The [vision](VISION.md) describes where this is going.

## Keep exploring

| You want to… | Start here |
| --- | --- |
| Learn by running code | [Your first program](documentation/learn/getting-started.md), then the [tour](documentation/learn/tour.md) |
| Build a useful script or service | [Common tasks](documentation/learn/common-tasks.md) |
| Look up an exact rule | [Core language](documentation/core-language/_index.md) |
| Find a standard type or function | `ms search_symbol <name or words>` and the [API reference](https://manuscript-lang.github.io/manuscript/standard-library/reference/) |
| Rerun a benchmark | [`bench/perf`](bench/perf/README.md) and [`bench/agent`](bench/agent/README.md) |
| Contribute | [Architecture](documentation/contributing/architecture.md), [development checks](documentation/contributing/development.md), [maintenance](documentation/contributing/maintenance.md) |
