+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Manuscript is a ground-up attempt to build the right language for a world where agents write most of the code and people have to understand, review and run it. That changes what a language optimizes for. The context an agent needs to make a change, how reliably its first draft compiles, how well the compiler's feedback steers the repair, how readable the result is to a reviewer, and how fast and small the program runs all matter together.

This page is the short version of the case. Every number has a script in the repository that reproduces it; links go to the result pages.

## Reads like Python, runs like native code

Agents already write `def`, four-space blocks, `lambda`, `for i in 0..n`, f-strings and `True`/`False` fluently, so that is the surface. Manuscript adds static types inferred where they are clear, `Optional` and `Result` with `try`, nominal records and alternatives with exhaustive `match`, and ownership checked by the compiler. It compiles ahead of time, through Cranelift for fast debug builds and LLVM for release, into one static executable with no runtime to install.

On seven whole-program kernels (sieve, n-body, life, matmul, trees, collatz, a counting map) Manuscript is faster than hand-written Go on every one, and level with Rust built with overflow checks on five; the widest remaining gap is n-body at 1.2x. On ten ordinary agent-written workloads it is faster than Go on eight and level with or ahead of Rust on six. See the [kernel](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/kernels/README.md) and [workload](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/workloads/results.md) results.

## Feedback an agent can act on

Diagnostics read `cause; fix`. When an agent writes `len(xs)`, `.unwrap()`, `name.toUpperCase()`, `fn`, `async` or `except`, the message names the Manuscript spelling instead of reporting a bare syntax error. When the repair is mechanical, the JSON diagnostic carries a byte-exact `fix` and `ms check --fix` applies it. A runtime fault from `ms run --json` or `ms test --json` is a document with a kind, a message that includes the remedy, a position and a trace, so the agent reads data rather than scraping stderr.

The rest of the agent surface is deliberately small, after an MCP server was tried and judged worse than a shell: `ms guide` prints the whole cheat sheet in under 4 KB, `ms search_symbol <words>` finds project and standard-library APIs in under 100 ms, and `ms verify` folds check, format, lint and test into one exit status. See [commands for agents](../developer-tooling/implementation.md#commands-for-agents) and [diagnostics](../developer-tooling/source/diagnostics.md).

## Concurrency without `async`

Any function can wait, so there is no `async`, no `await` and no function coloring. A `TaskGroup` runs cooperative tasks on one thread, a `WorkerGroup` runs isolated entries on OS threads, and a `ProcessGroup` runs them in child processes. All three own their work inside a `with` block, cancel what is still running when the block ends, and communicate over typed channels. Values move into tasks and come back as results or messages; `Shared[T]` is the one explicit, reference-counted way to share.

Eight CPU-bound jobs over four workers run 3.95x faster than over one ([worker scaling](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/workers/README.md)). An adversarial soundness review ran over a hundred probes against the task, worker and process runtimes, filed 21 issues, and all but two are fixed on `main`; deadlocks are reported as a fault with both stacks, and cancellation releases owned locals, closes sockets and kills children. Read [concurrency](../core-language/concurrency/_index.md) for the rules.

## Ownership you can follow

Records, lists, maps, strings and alternatives are values with one owner. The compiler moves them at their last use, borrows them for reads and drops them deterministically, with no tracing collector and no reference counting on ordinary data. `var` marks mutation at the declaration and at the call, `.clone()` marks a copy, borrows are lexical with no lifetimes in source, and `with` scopes external resources.

The payoff is visible in a server: the same HTTP service on Manuscript's standard library and on Go's `net/http` answers `/health` at 76-82k requests per second against 55k, with a p99 of 2.9-4.3 ms against 5.6 ms, on two threads instead of 67, and holds 10,000 idle connections in 31 MB where Go uses 197 MB. Where Go is ahead, file and DNS calls that block the runtime thread, is on the same page: [web results](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/web/results.md). The exact rules are in [references and borrowing](../core-language/types/references.md).

## Batteries included

A language for agents has to cover what programs actually do without a package hunt. The standard library ships files, streams, processes, HTTP client and server, TCP, JSON and JSON streaming, CSV, TOML, YAML, HTML, time, crypto, random, regex, logging, decimal, semver, archives, sized numerics (`Int8` to `Int64`, `Float32`, packed in memory) and a test runner, all in `ms`. Most of it is written in Manuscript itself; Rust is reserved for small, general runtime primitives.

It is also fast: `@std/json` parses and writes the standard documents faster than V8 on every row, from 1.2x on a small RPC message to 2.6x parsing `canada.json` and 3.5x writing `twitter.json` ([JSON results](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/json/results.md)).

## Measured against agents

The claim that matters most is also the one that is hardest to assume: that agents do better in Manuscript. The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) gives the same twenty challenges (ten small programs, ten applications of three to five thousand lines) to a coding agent in Manuscript, TypeScript, Go and Rust, with hidden tests, and records pass rate, first-build success, turns, tokens and cost over passing runs only.

In the latest runs with Claude Haiku, agents pass 10 of 10 small challenges in Manuscript, the same as in TypeScript, and 8 of 10 large applications. They still need several compile-fix rounds (first build succeeds on 1 or 2 of 10) and write about a fifth more source than in TypeScript. Those two numbers are what the diagnostics, the cheat sheet and the API work are trying to move; the [results](https://github.com/manuscript-lang/manuscript/tree/main/bench/agent/results) record each attempt.

## Where this is going

Manuscript is in alpha. Syntax and APIs still change, and the ambition in the [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) is broader than what ships: a language and toolchain an agent-driven team can start with and stay with, from a script to a deployed service, while people keep a clear view of the result.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
