+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Manuscript is a ground-up attempt to build the ideal programming language for the agentic era. Its starting point is the relationship between an agent producing software, a person understanding it, and tools analyzing whether the result does what was intended.

That changes what the language optimizes for. Token use, the amount of context needed to make a change, the clarity of the generated code, and the quality of compiler feedback all matter alongside execution performance.

## Learn from agents, improve the language

We exercise coding agents on real programming tasks and inspect the results: where they hesitate, which syntax they reach for, how they respond to diagnostics, and whether their solutions pass tests. The [agent benchmark](https://github.com/manuscript-lang/manuscript/tree/main/bench/agent) records outcomes, tokens, turns, time, and cost. These observations inform changes to syntax, APIs, documentation, and the toolchain.

The aim is a language that improves with evidence from the work it is designed for. A familiar spelling can help an agent get the first draft right; a precise diagnostic can shorten the repair loop; a simpler API can remove the need for that repair altogether.

## Use fewer tokens without losing meaning

An agent repeatedly reads source, writes changes, and consumes tool output. Manuscript aims to make that context efficient through a compact syntax, a small set of regular concepts, inferred types where they are clear, and concise tools such as `ms guide` and `ms search_symbol`.

Readability and analysis are part of the same goal. A shorter expression should still expose intent. Types, visible mutation, explicit error values, and flat control flow help people and tools follow what a program does. Token counts are measured in the benchmark; universal savings are not assumed.

## Make programs understandable to people and tools

Static types and regular structure give analysis a foundation in the language itself. The compiler checks source, diagnostics name actionable repairs, and inspection and diagrams expose program structure. Agents and reviewers can work from the same evidence.

Manuscript is in alpha. The features below describe current source; the ambition is broader than the implementation, and published archives may lag behind.

## Read the program, understand the intent

- **Familiar building blocks.** `def` functions, four-space blocks, `True` and `False`, typed records, and `case` alternatives keep ordinary programs direct. `0..count` counts without a range import; `lambda` and `Callable` make callbacks explicit.
- **Typed boundaries.** `Optional` represents absence, `Result` represents expected failure, and `try` propagates an error. JSON can decode straight into application records; unknown shapes use `JsonValue`.
- **Visible data flow.** Pipe flows pass results from one operation to the next. Parameters can borrow values; `var` marks mutation and `.clone()` requests a copy. The [ownership rules](../core-language/types/references.md) explain when values move.
- **Scoped work.** `with` scopes resources. Task groups coordinate cooperative work on one thread, worker groups run isolated entries on threads, and process groups supervise subprocesses. [Concurrency](../core-language/concurrency/_index.md) explains how to choose between them and their communication contracts.

Start with the [language tour](tour.md) to see these ideas in small, runnable examples.

## Tools for agents and their reviewers

| Command | What it helps you do |
| --- | --- |
| `ms guide` | Read the compact language cheat sheet |
| `ms search_symbol <words>` | Find project and standard-library APIs by name or description |
| `ms check --json`, `ms lint --json` | Consume structured findings |
| `ms check --fix`, `ms lint --fix` | Apply available mechanical repairs, then review the result |
| `ms verify` | Run type, formatting, lint, and test checks together |
| `ms inspect`, `ms review`, `ms diagram` | Inspect the checked program, a change, or a call graph |

The language server supports editor navigation and diagnostics. Native fault reports and `ms profile` connect execution back to `.ms` source. See [developer tools](../developer-tooling/implementation.md) for the commands and [debugging](../developer-tooling/debugging/_index.md) for current attribution limits.

## From source to an executable

`ms` brings the compiler, formatter, linter, test runner, language server, and profiler together. The first link downloads a pinned linker; Release builds also fetch LLVM tools and cache them. Build outputs run without `ms` installed. See [how it works](../developer-tooling/how-it-works.md) and the [platform requirements](../contributing/rust-toolchain.md#differences-users-can-see).

The standard library covers files, processes, HTTP, networking, JSON, text, and time. Explicit numeric widths and conversions let programs choose storage where it matters; the defaults remain 64-bit `Int` and `Float`.

## Learn from measured results

The project uses two kinds of feedback: [runtime benchmarks](https://github.com/manuscript-lang/manuscript/tree/main/bench/perf) exercise generated code, and [agent benchmarks](https://github.com/manuscript-lang/manuscript/tree/main/bench/agent) check what agents build against test oracles. Their commands, workloads, and recorded results make improvements inspectable. Results describe those runs, not every program or model; rerun them when comparing another compiler revision or machine.

The [vision](https://github.com/manuscript-lang/manuscript/blob/main/VISION.md) describes the longer-term goal: agents can do more implementation while people retain a clear view of the result.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
