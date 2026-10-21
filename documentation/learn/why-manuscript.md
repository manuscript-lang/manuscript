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

- [`bench/perf`](https://github.com/manuscript-lang/manuscript/tree/main/bench/perf) compares generated code with hand-written Go. Whole-program kernels run on par with Go (0.43x to 1.39x of its time; sieve, life, and trees are faster). Single-operation microbenchmarks range from faster to about 4x slower, and closing those gaps is the current optimization target.
- [`bench/agent`](https://github.com/manuscript-lang/manuscript/tree/main/bench/agent) runs the same challenges in Manuscript, Go, TypeScript, and Rust. Failures there drive diagnostics, docs, and the cheat sheet. Manuscript currently trails the others on pass rate and cost; closing that gap is the point of the project.

## Try it

[Run your first program](getting-started.md), then take the [language tour](tour.md).
