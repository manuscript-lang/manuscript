# Manuscript

**The language for the agentic era.**

Manuscript is a statically typed, natively compiled language designed for agents to write and humans to understand. It combines familiar, Python-like syntax with ownership, concurrency without `async`, and compiler feedback that helps agents repair their code. The compiler, standard library, formatter and test runner ship in one `ms` binary.

[Get started](documentation/learn/getting-started.md) · [Language tour](documentation/learn/tour.md) · [Why Manuscript](documentation/learn/why-manuscript.md) · [The book](https://manuscript-lang.github.io/manuscript/) · [Releases](https://github.com/manuscript-lang/manuscript/releases)

```manuscript
from "@std/json.ms" import parse
from "@std/test.ms" import expect_equal

type Config:
    host: String = "127.0.0.1"
    port: Int = 8080

test "read configuration with defaults":
    let config = try parse[Config]("{\"port\":9000}")
    try expect_equal(config.host, "127.0.0.1")
    try expect_equal(config.port, 9000)
    try expect_equal(parse[Config]("{\"port\":true}").is_error(), True)
```

Save it as `config.ms` and run `ms test config.ms`. JSON decodes into a record, missing fields take their defaults, and a wrong field type returns an error. `try` propagates a failed assertion so the test fails. [Set up `ms` first](documentation/learn/getting-started.md) if you are new to the language.

Manuscript is in alpha: syntax, APIs and platform behavior can change, and these docs follow `main`.

## Why Manuscript

**Reads like Python, runs like native code.** `def`, four-space blocks, `lambda`, `for i in 0..n`, f-strings and `True`/`False` give the language a familiar surface. The compiler infers types, checks ownership and emits machine code through Cranelift (debug) or LLVM (release). The recorded kernel run was faster than Go on all seven cases and within 6% of or faster than overflow-checked Rust on five ([numbers below](#measured-not-asserted)).

**Feedback an agent can act on.** Diagnostics are `<cause>; <fix>`. Habits from Python, TypeScript, Go and Rust get a named replacement, and mechanical repairs carry a byte-exact `fix` that `ms check --fix` applies. `ms run --json` reports a runtime fault with a kind, a position and a trace. See [written for agents](#written-for-agents).

**Concurrency without `async`.** Any function can wait. A `TaskGroup` runs cooperative tasks on one thread, a `WorkerGroup` runs isolated entries on OS threads, and a `ProcessGroup` runs them in child processes. All three use typed channels and scoped cleanup. A recorded CPU-bound run achieved 3.95x scaling from one to four workers ([worker results](bench/perf/workers/README.md)). Adversarial reviews probe the runtime for leaks, hangs and unsound sharing.

**Ownership you can follow, no garbage collector.** Values have one owner and are dropped deterministically. `var` marks mutation at the declaration and at the call (`reset(var counter)`), `.clone()` makes copies visible, and borrows are lexical with no lifetimes in source. The [HTTP measurements](#http-server-against-go-nethttp) include throughput, latency and memory, alongside the cases where Manuscript is slower.

**A growing standard library.** Files, streams, processes, HTTP client and server, TCP, JSON, CSV, TOML, YAML, time, crypto, regex, logging, command-line parsing and tests are available in `ms`. Find APIs with `ms search_symbol <words>`. A batteries-included environment is the direction; the alpha library is still growing.

**Measured, not asserted.** The [agent benchmark](bench/agent/README.md) gives the same twenty challenges to a coding agent in Manuscript, TypeScript, Go and Rust with hidden tests, and the [performance benchmarks](bench/perf/README.md) pin every speed claim to a script, a machine and a revision. Both are in this repository, including the results that are not flattering yet.

## Measured, not asserted

These are recorded runs, not measurements of every new revision: `c1b81215` (2026-10-25) unless noted, Linux x86-64, four cores, Go 1.24.7, rustc 1.99.1, Node 22, `ms` Release build with LLVM. In the time-ratio columns, below 1.00x means Manuscript took less time; the JSON table labels throughput ratios separately. Compare numbers from one machine and rerun for your workload.

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

This run was faster than Go on 8 of 10; CSV grouping and ciphers took longer. Six cases were within 1% of or faster than Rust. The four slower cases were string-heavy; see the result page for that revision's analysis.

### JSON against Node (V8)

`@std/json` `parse` and `stringify` against `JSON.parse` and `JSON.stringify` on the standard documents, using `JsonValue` trees. Typed record parsing uses a separate path. MB per second, median of at least five runs after warm-up. Four runs here agree within a few percent; on another machine the twitter parse and citm stringify rows came in just under Node (0.94x and 0.88x), so the recorded range is about 0.9-3.5x across hardware. Reproduce: `sh bench/perf/json/run.sh`; details in [`bench/perf/json/results.md`](bench/perf/json/results.md).

| document | parse: Node | parse: Manuscript | speed | stringify: Node | stringify: Manuscript | speed |
|---|---:|---:|---:|---:|---:|---:|
| small RPC message | 190 | 230 | 1.21x | 299 | 352 | 1.18x |
| twitter.json | 569 | 770 | 1.35x | 364 | 1,266 | 3.48x |
| canada.json | 162 | 419 | 2.58x | 128 | 355 | 2.78x |
| citm_catalog.json | 671 | 904 | 1.35x | 908 | 1,269 | 1.40x |

### HTTP server against Go `net/http`

The same server on Manuscript's standard library and on Go, shared 4-CPU VM, server on 2 CPUs and load on the other 2. This table is the dated run at `6003f16b` (2026-10-25), including its memory tradeoff. Reproduce: `sh bench/perf/web/run.sh 5`; later experiments and full tables are in [`bench/perf/web/results.md`](bench/perf/web/results.md#2026-10-25).

| measurement | Manuscript | Go |
|---|---:|---:|
| `/health` requests per second | 81.5k-92.4k | 61.4k-62.4k |
| `/health` p99 latency | 2.5 ms | 5.2-5.3 ms |
| `/io` requests per second | 490-546 | 707-728 |
| threads | 6 | 68 |
| resident memory after load | 70 MB | 15 MB |
| resident memory with 10,000 idle connections | 93 MB | 197 MB |
| system calls in 5 idle seconds | 2 | 72 |

In this run, `/io` throughput was lower and memory after load was higher than Go's. Earlier results on the linked page predate whole-file I/O offload; they do not describe current file-call behavior.

### Agents writing Manuscript

The [agent benchmark](bench/agent/README.md) runs Claude Code on twenty challenges (ten small programs, ten applications of three to five thousand lines) with hidden tests, one trial per cell, and records pass rate, first-build success, turns, tokens and cost over passing runs only. Latest results ([2026-10-21](bench/agent/results/summary-2026-10-21.md), [2026-10-22](bench/agent/results/summary-2026-10-22.md), Claude Haiku):

| | Manuscript | TypeScript |
|---|---:|---:|
| small challenges passed | 9 / 10 (Oct 21), 10 / 10 (Oct 22) | 10 / 10 (Oct 21) |
| large applications passed | 8 / 10 | not run |
| first build succeeded (small) | 1-2 / 10 | 10 / 10 |
| source size, LLM tokens, nine shared passing challenges | 1.30x (Oct 21), 1.28x (Oct 22), about 1.21x (terse rerun) | 1.00x |

The October 22 compact-guide run reached 10/10 in Manuscript; the terse-guide rerun reached 9/10. Manuscript needed more compile-fix rounds and about 20-30% more source tokens on the compared challenges. The first-build rate and token ratio remain targets for improvement; one trial per cell does not establish a general success rate.

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

When a repair is mechanical, the JSON diagnostic carries it and `ms check --fix` applies it. For a misspelled call to `double`, the diagnostic includes:

```json
{"code": "MS2001", "message": "unknown binding duoble; did you mean 'double'?",
 "fix": {"position": {"line": 3, "column": 22}, "end": {"line": 3, "column": 28}, "replacement": "double"}}
```

A fault at runtime is data too. `ms run program.ms --json` on an out-of-range index exits with the fault status and a `fault` object: `"kind": "index_out_of_range"`, the message with its remedy (`pass a default: get(index:, default: ...)`), the position, the trace, and whether `with` cleanups ran.

Start with these commands:

| Command | What it gives an agent |
| --- | --- |
| `ms guide` | A compact language cheat sheet with a complete program |
| `ms search_symbol <words>` | Bounded fuzzy lookup over the project and standard library; `<module>` or `<module>.<Name>` prints that page |
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
from "@std/test.ms" import expect_equal, expect_ok

def square(n: Int) -> Int:
    return n * n

test "a group collects its results in start order":
    with let group = TaskGroup[Int]():
        for n in [1, 2, 3]:
            group.spawn(lambda ch: square(n))
        group.results() | try expect_ok | try expect_equal([1, 4, 9])
```

Tasks own their captured values; results come back through `result()` or the channel. `Shared[T]` provides explicit reference-counted sharing. Collect results before leaving the group, since scope exit cancels unfinished work. Closing a task group also closes handed-out channels, including handles retained after result collection. Read [concurrency](documentation/core-language/concurrency/_index.md) for cleanup limits, fault reporting and the scope of deadlock detection; isolation is an execution model, not a security sandbox.

## Ownership and visible mutation

Records, lists, maps, strings and alternatives are values with one owner. The compiler moves values at their last use, borrows them for reads, and drops them deterministically; ordinary data needs no tracing collector or reference counting. `var` makes mutation visible, `.clone()` makes copying visible, and `with` scopes external resources. The exact rules are in [references and borrowing](documentation/core-language/types/references.md) and [resource cleanup](documentation/core-language/cleanup/_index.md).

## Try it

[Build from source](#build-from-source) or extract a [release archive](https://github.com/manuscript-lang/manuscript/releases) for your platform. Add the directory containing `ms` to your `PATH` (`target/release` for a source build), then start a project from a directory of your choice:

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
ms test ms.toml
ms build ms.toml -o hello
./hello first second
```

The program prints `Arguments: 2`, and the built executable runs without `ms` installed. On Windows, build with `-o hello.exe` and run `.\hello.exe first second`. The first native link downloads a pinned, checksum-verified linker into the cache; Release builds also fetch LLVM tools once. Plan for network access on first use, or configure local tools as described in [how it works](documentation/developer-tooling/how-it-works.md). Follow [your first program](documentation/learn/getting-started.md) to edit and rerun it.

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
