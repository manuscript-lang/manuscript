+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Manuscript is designed for agents to write and people to understand. Its small language, compiler feedback and native toolchain support one workflow: write a program, catch mistakes, review the important decisions, and build an executable.

## Read the code, ship the executable {#familiar-to-read-native-to-run}

Manuscript chooses a small type system with generics, no `any` escape hatch and no runtime reflection API. Every expression has a compiler-checked type, including values used through interface contracts. This keeps data shapes and operation signatures available to analysis while catching mismatched data and calls before execution. `Result` makes expected failures visible, exhaustive `match` checks every alternative, and ownership tells you where a value can change or move. In review, `var` marks mutation and `.clone()` marks an explicit copy.

The same `ms` command checks, formats, tests and builds your project. Use debug builds while iterating and optimized release builds when sharing your program. The executable runs without Manuscript installed. See [build levels](../developer-tooling/builds/build-levels.md) for deployment choices.

## Understand what your agent built

`ms diagram ms.toml --format html -o code-map.html` turns the checked program into one interactive file you can open offline. Read the source beside its call graph, inspect identifier types, and explore behavior and sequence views alongside parameter borrow modes. A diff overlay highlights the declarations a change touches, so you can move from a broad overview to the code that needs attention.

The map presents checked source relationships. Tests and profiling show how the program behaves when run. Pair it with `ms review --diff` to prioritize changed contracts, error flow and resource scopes. See [the interactive code map](../developer-tooling/implementation.md#interactive-code-map).

## Feedback an agent can act on

Diagnostics read `cause; fix`. When an agent writes `len(xs)`, `.unwrap()`, `name.toUpperCase()`, `def`, `async` or `except`, the message names the Manuscript spelling instead of reporting a bare syntax error. When the repair is mechanical, the JSON diagnostic carries a byte-exact `fix` and `ms check --fix` applies it. A runtime fault from `ms run --json` or `ms test --json` is a document with a kind, a message that includes the remedy, a position and a trace, so the agent reads data rather than scraping stderr.

`ms guide` prints a compact language cheat sheet, `ms search_symbol <words>` finds project and standard-library APIs with bounded output, and `ms verify` folds type checking, formatting checks, lint and tests into one exit status. See [commands for agents](../developer-tooling/implementation.md#commands-for-agents) and [diagnostics](../developer-tooling/source/diagnostics.md).

## Concurrency without `async`

Any function can wait, so there is no `async`, no `await` and no function coloring. `promise(fn: ...)` starts concurrent work and returns a `Promise[T]`; `wait()` takes its result. Streams are pulled lazily. Promises can read borrowed captures; mutable state stays with one owner and updates travel over a `pipe`. A resource moved into a promise belongs to that work. Dropping an unfinished promise cancels it and waits for it to end.

Cancellation is cooperative at waits. The [concurrency guide](../core-language/concurrency/_index.md) explains how to coordinate work and handle its results.

## Ownership you can follow

Records, lists, maps, strings and alternatives are values with one owner. The compiler moves them at their last use, borrows them for reads and drops them deterministically, with no tracing collector and no reference counting on ordinary data. `var` marks mutation at the declaration and at the call, `.clone()` marks a copy, borrows are lexical with no lifetimes in source, and a scope closes the external resources bound in it. Functions can return borrowed parts of arguments, including through `Optional` or `Result`; `try` preserves the active case's ownership instead of copying its payload. The owner must remain available while the returned borrow is used.

See [references and borrowing](../core-language/types/references.md) for the exact rules, including how long a returned borrow remains valid. Bind files and connections in the [scope that needs them](../core-language/cleanup/scopes.md) so they close on exit, and flush fallible writes before closing to observe errors.

## Batteries-included standard library {#a-growing-standard-library}

The standard library includes files, streams, processes, HTTP client and server, TCP, JSON and other data formats, time, crypto, regex, logging, command-line parsing and a test runner. Discover what's available with `ms search_symbol <words>` or browse the [API reference](../standard-library/reference/_index.md). Most library code is written in Manuscript; native primitives are implemented in Rust.

For a known JSON shape, `parse[Config](text)` decodes directly into your record. Defaults handle omitted fields; shape mismatches return a `Result` error. This avoids building and walking a public JSON tree just to read configuration. Use `JsonValue` for unknown shapes. Start with the [JSON recipes](common-tasks.md) and [typed configuration example](best-practices.md#let-types-describe-your-data).

## Measured against agents

The [agent benchmark](https://github.com/manuscript-lang/manuscript/blob/main/bench/agent/README.md) measures correctness, repair rounds, tokens and cost on programs with hidden tests. Dated results and reproduction instructions let you assess its progress on the tasks you care about.

The [performance suites](https://github.com/manuscript-lang/manuscript/blob/main/bench/perf/README.md) cover kernels, data formats, HTTP and concurrent work. Each result belongs to a particular revision, workload and machine. Use those reproduction commands to assess your workload.

## Where this is going

Manuscript is in alpha, with evolving syntax and APIs. The [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) is a language and toolchain an agent-driven team can grow with, from a script to a deployed service, while people keep a clear view of the result.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
