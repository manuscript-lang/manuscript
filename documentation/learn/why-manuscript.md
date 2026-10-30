+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Manuscript is a ground-up attempt to build the right language for a world where agents write most of the code and people have to understand, review and run it. That changes what a language optimizes for. The context an agent needs to make a change, how reliably its first draft compiles, how well the compiler's feedback steers the repair, how readable the result is to a reviewer, and how fast and small the program runs all matter together.

This page is the short version of the case. Every number has a script in the repository that reproduces it; links go to the result pages.

## Familiar to read, native to run

The surface is four-space blocks, `fn`, `for i in 0..n`, interpolated `"{name}"` strings and `true`/`false`. It is deliberately not Python: an agent that writes `def`, `lambda`, `True` or `elif` out of habit gets a diagnostic naming the Manuscript spelling instead of code that merely looks right. Manuscript adds static types inferred where they are clear, `Optional` and `Result` with `try`, nominal records and alternatives with exhaustive `match`, and ownership checked by the compiler. It compiles ahead of time, through Cranelift for fast debug builds and LLVM for release, into one static executable with no runtime to install.

In the recorded seven-kernel run, Manuscript took less time than Go on all seven and was within 6% of or faster than overflow-checked Rust on five. The slowest ratio against checked Rust was n-body at 1.23x. In the ten-workload run, eight cases were faster than Go and six were within 1% of or faster than Rust. These are measurements of particular revisions and machines; see the [kernel](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/kernels/README.md) and [workload](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/workloads/results.md) results and reproduction commands.

## Feedback an agent can act on

Diagnostics read `cause; fix`. When an agent writes `len(xs)`, `.unwrap()`, `name.toUpperCase()`, `def`, `async` or `except`, the message names the Manuscript spelling instead of reporting a bare syntax error. When the repair is mechanical, the JSON diagnostic carries a byte-exact `fix` and `ms check --fix` applies it. A runtime fault from `ms run --json` or `ms test --json` is a document with a kind, a message that includes the remedy, a position and a trace, so the agent reads data rather than scraping stderr.

`ms guide` prints a compact language cheat sheet, `ms search_symbol <words>` finds project and standard-library APIs with bounded output, and `ms verify` folds check, format, lint and test into one exit status. See [commands for agents](../developer-tooling/implementation.md#commands-for-agents) and [diagnostics](../developer-tooling/source/diagnostics.md).

## Concurrency without `async`

Any function can wait, so there is no `async`, no `await` and no function coloring. A `TaskGroup` runs cooperative tasks on one thread, a `WorkerGroup` runs isolated entries on OS threads, and a `ProcessGroup` runs them in child processes. All three own their work until the binding that holds the group goes out of scope, cancel what is still running then, and communicate over typed channels. Values move into tasks and come back as results or messages; `Lock[T]` is the one explicit, reference-counted way to share.

A recorded eight-job run achieved 3.95x scaling from one to four workers ([worker scaling](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/workers/README.md)). Adversarial reviews probe the task, worker and process runtimes for leaks, hangs and unsound sharing. Cleanup, fault containment and deadlock detection have limits; read [concurrency](../core-language/concurrency/_index.md) before choosing a boundary.

## Ownership you can follow

Records, lists, maps, strings and alternatives are values with one owner. The compiler moves them at their last use, borrows them for reads and drops them deterministically, with no tracing collector and no reference counting on ordinary data. `var` marks mutation at the declaration and at the call, `.clone()` marks a copy, borrows are lexical with no lifetimes in source, and a scope closes the external resources bound in it.

The web benchmark records both benefits and costs. The October 25 run at `6003f16b` used 93 MB for 10,000 idle connections versus Go's 197 MB, but memory after load was higher (70 MB versus 15 MB) and `/io` throughput was lower. See the dated [web results](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/web/results.md#2026-10-25) and later experiments. The language's exact rules are in [references and borrowing](../core-language/types/references.md).

## A growing standard library

A batteries-included environment is the goal. The standard library already includes files, streams, processes, HTTP client and server, TCP, JSON and other data formats, time, crypto, regex, logging, command-line parsing and a test runner. Discover what's available with `ms search_symbol <words>` or browse the [API reference](../standard-library/reference/_index.md). Most library code is written in Manuscript; native primitives are implemented in Rust.

The [JSON benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/json/results.md) measures `JsonValue` parsing and encoding, from a small RPC message to `twitter.json`. The recorded range across machines is about 0.9x to 3.5x V8's throughput. Typed record parsing uses a separate path.

## Measured against agents

The claim that matters most is also the one that is hardest to assume: that agents do better in Manuscript. The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) gives the same twenty challenges (ten small programs, ten applications of three to five thousand lines) to a coding agent in Manuscript, TypeScript, Go and Rust, with hidden tests, and records pass rate, first-build success, turns, tokens and cost over passing runs only.

The recorded [October 21](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/results/summary-2026-10-21.md) Claude Haiku run passed 9 of 10 small challenges in Manuscript, 10 of 10 in TypeScript, and 8 of 10 large applications in Manuscript. The [October 22](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/results/summary-2026-10-22.md) compact-guide run reached 10 of 10 small challenges in Manuscript; the terse-guide rerun reached 9 of 10. There was one trial per cell. Manuscript needed several compile-fix rounds (first build succeeded on 1 or 2 of 10) and about 20-30% more source tokens on the compared small challenges. First-build success and source size remain targets for improvement.

## Where this is going

Manuscript is in alpha. Syntax and APIs still change, and the ambition in the [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) is broader than what ships: a language and toolchain an agent-driven team can start with and stay with, from a script to a deployed service, while people keep a clear view of the result.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
