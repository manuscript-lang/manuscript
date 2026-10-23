+++
title = "Why Manuscript"
weight = 6
+++

# Why Manuscript

Manuscript is a statically typed language built for the loop an agent runs: write, check, fix, verify, ship. It compiles to a native executable. Everything below is on main today.

## A language with little to get wrong

- **No hidden control flow.** Failure is a value: `Optional` and `Result`, propagated with `try`. There are no exceptions, no implicit conversions, and no truthiness.
- **No async syntax.** Files, networking, HTTP, and JSON are `@std` functions called like any other.
- **Flat, readable code.** Four-space blocks, exhaustive `match` over alternatives, and `|` pipe flows that replace nested calls and `Result` matches.
- **Less ceremony.** `+=` and friends, `range(a, b)` as a counter loop, string interpolation, defaults and labels, and `[]` indexing that the checker accepts when bounds are proven.
- **Typed data.** `json.parse[T]` reads JSON straight into your records; nominal types, generics, and interfaces with explicit `impl` blocks keep boundaries clear.
- **Cleanup that stays correct.** `with` closes files and connections at block end, on errors and cancellation too.

## Tools that give evidence, not prose

| Command | Gives you |
| --- | --- |
| `ms check`, `lint`, `test`, `build`, `inspect` with `--json` | Structured diagnostics an agent can act on |
| `ms search_symbol <words>` | Exact standard-library and project signatures |
| `ms guide` | The language cheat sheet |
| `ms verify` | Check, format, lint, and test in one result |
| `ms review`, `ms diagram` | Deterministic views of a change and of the call graph |

The language server, VS Code extension, source-level debugger, and CPU, heap, and trace profiling all work on `.ms` lines.

## One binary, native result

`ms` is the compiler, formatter, linter, test runner, language server, and profiler. Download it and run; there is no separate toolchain to install. No executable cache means a stale binary never runs.

## Measured, not claimed

- [`bench/perf`](https://github.com/manuscript-lang/manuscript/tree/main/bench/perf) compares generated code with hand-written Go and Rust. Across 31 benchmarks Manuscript is faster than Go on 26, and as low as 0.14x of Go's time; release builds use LLVM on Linux and macOS. With Rust's overflow checks on, Manuscript is typically within 1.4x of Rust, and sorting is within 1.2x. Both are measured, not promised.
- [`bench/agent`](https://github.com/manuscript-lang/manuscript/tree/main/bench/agent) runs the same challenges in Manuscript, Go, TypeScript, and Rust. Failures there drive diagnostics, docs, and the cheat sheet. On the latest Haiku 5.5 run, agents pass 9 of 10 small challenges and 8 of 10 large applications in Manuscript, with source 1.30x TypeScript's size in LLM tokens.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
