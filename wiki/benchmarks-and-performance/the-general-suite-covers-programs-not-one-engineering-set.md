[Wiki](../index.md) › [Benchmarks and performance](index.md)

# The general suite covers many kinds of program, against Rust, Go and Node

Decision: Manuscript is general purpose, so program-level perf work uses `bench/perf/suite/` (interpreters, graphs, allocation, numeric, dispatch, crypto, compression, parsing, regex, JSON, strings, concurrency, files, text), one directory per program with `main.ms`, `main.rs`, `main.go`, `main.js` and sometimes `main.c`. The old `engineering/` set is folded in. Add a program there, with the other languages, instead of a new top-level benchmark directory.

Verified (2026-11-14): the first run found gaps only where the runtime does work a language idiom hides: `s += non_literal` is quadratic, 100k tiny promises are slower on 4 threads than on 1, a `var` cursor over a linked list copies the tail per step, and directory walking is 3.6x C. Pure compute programs were level with Rust. A new perf claim should say which of these areas it moves.

Evidence: [`bench/perf/suite/results.md`](../../bench/perf/suite/results.md).

Apply when: adding a benchmark, choosing what to optimize, or claiming Manuscript is as fast as Rust.
