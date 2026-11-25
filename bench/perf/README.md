# Performance benchmark

How fast Manuscript is, compared with hand-written Go and Rust, Node's JSON, and across the standard library. This measures the compiler and runtime only; no agents are involved. For how well agents write programs in different languages, see [`bench/agent/`](../agent/README.md). The two never share results.

This is the one performance suite. [`groups.txt`](groups.txt) indexes every group (area, kind, command, results page) and one runner runs them:

```sh
make perf-list                              # every group, its command and results page
make perf GROUP=suite SAMPLES=5             # one group; GROUP=<area> runs an area (programs, kernels, operations, io, concurrency, compile, counts); GROUP=time every timing group
make perf-check                             # the index is complete and every results page exists (part of `make bench-check`)
```

`ms run bench/perf/tools/perf.ms -- run <group> [samples]` is the same without make, and each group's own command in the table below still works. Comparisons against C use checked C. A new benchmark is a new row in `groups.txt` and in the table, with its results page; a finished investigation is deleted once its finding is in the wiki. `perf-check` fails on a group without a results page or README row, and on a path under `bench/perf/` that is not a group's. 

| Directory | Measures | Run | Results |
| --- | --- | --- | --- |
| [`stdlib`](stdlib) | ns per operation for each standard-library case (Manuscript only) | `make stdlib-bench` | `stdlib/results.md` |
| [`programs`](programs) | the same pure-Manuscript programs against hand-written Go and Rust, as a ratio | `MS=.artifacts/build/release/src/cli/ms GO=go ms run bench/perf/tools/programs.ms -- 7` | [`results.md#programs`](results.md#programs) |
| [`llvm-release`](llvm-release.md) | LLVM against Cranelift on all 31 benchmarks | see the page | [`llvm-release.md`](llvm-release.md) |
| [`kernels`](kernels) | whole numeric and data-structure kernels (sieve, n-body, life, matmul, trees, collatz, Int map) against hand-written Go and Rust | `MS=.artifacts/build/release/src/cli/ms GO=go ms run bench/perf/tools/kernels.ms -- kernels 5` | [`kernels/README.md`](kernels/README.md) |
| [`workloads`](workloads) | ordinary agent-style programs (parsing, strings, maps, stdin) against Go and Rust on ~3 MB of input, outputs compared | `MS=.artifacts/build/release/src/cli/ms ms run bench/perf/tools/workloads.ms -- 3` | [`results.md#workloads`](results.md#workloads) |
| [`suite`](suite) | 23 whole programs by area (interpreters, graphs, allocation, numeric, abstraction, crypto, compression, parsing, regex, JSON, strings, concurrency, files, text and data) against Rust, Go, Node and C, outputs compared | `MS=.artifacts/build/release/src/cli/ms sh bench/perf/suite/run.sh 5` | [`results.md#suite`](results.md#suite) |
| [`guards`](guards) | small programs, one per recent speed fix (signature tables, regex prefilter, image codecs, fused chains, map probes, scope-end close, a stored-to Result variable, string append), counted in instructions | `make perf-counts` (nightly on main) | [`counts.txt`](counts.txt) |
| [`datastructures`](datastructures) | core List, Map, Set, String, Bytes, PriorityQueue and SortedMap operations against Go and Rust, ns per operation | `MS=.artifacts/build/release/src/cli/ms ms run bench/perf/tools/datastructures.ms -- 5` | [`results.md`](results.md#datastructures) |
| [`element-types`](element-types) | List, Map, Set, Deque, PriorityQueue, sort, Optional and Result over records, payload enums and generics against Rust | `MS=.artifacts/build/release/src/cli/ms sh bench/perf/element-types/run.sh 5` | [`README.md`](element-types/README.md) |
| [`sort-shapes`](sort-shapes) | `sorted` and `sort` by a comparator over 1M plain and owning records with many and few distinct keys and nearly sorted input, against Rust | `MS=.artifacts/build/release/src/cli/ms sh bench/perf/sort-shapes/run.sh 7` | [`README.md`](sort-shapes/README.md) |
| [`codecs`](codecs) | paired typed JSON Base64 and syntax-error loops with exact output validation | see the [protocol](codecs/README.md) | [2026-10-29](codecs/results-2026-10-29.md) |
| [`csv`](csv) | `@std/csv` parse against the Rust `csv` crate on 5000 generated rows | `MS=.artifacts/build/release/src/cli/ms ms run bench/perf/tools/cargo_vs_ms.ms -- csv` | [`csv/README.md`](csv/README.md) |
| [`csv-streams`](csv-streams) | fragmented CSV record scaling, whole-chunk and malformed-input controls | see the [protocol](csv-streams/README.md) | [2026-11-10](csv-streams/README.md) |
| [`json`](json) | `@std/json` parse and stringify against Node (V8) on twitter, canada and citm_catalog | `ms run bench/perf/tools/json_bench.ms` | [`results.md#json`](results.md#json) |
| [`streams`](streams) | stream pipelines (`map`, `lines`, `collect`) against the loops they replace, ns per item | see the [page](streams/README.md) | [`streams/README.md`](streams/README.md) |
| [`iface`](iface) | ns per interface call: local, returned and passed values against a direct loop | see the [page](iface/README.md) | [`iface/README.md`](iface/README.md) |
| [`web`](web) | the same HTTP server on Manuscript's standard library and Go's `net/http`: throughput, latency, memory, system calls, idle connections, file and DNS handlers | `sh bench/perf/web/run.sh 5` | [`results.md#web`](results.md#web) |
| [`tasks`](tasks) | resident memory and page tables per parked promise task at 100k and 1M, spawn and cancel time | `ms run bench/perf/tasks/main.ms -- 1000000 sleep` | [`tasks/README.md`](tasks/README.md) |
| [`mailbox`](mailbox) | ns per promise through the scheduler mailboxes (cross-thread start and event traffic) | `ms run bench/perf/mailbox/main.ms -- 100000 5` | [`mailbox/README.md`](mailbox/README.md) |
| [`async-primitives`](async-primitives) | probe: ns per promise start and wait, pipe round trip and timer at 1 and 4 threads against Go and tokio | see the [page](async-primitives/README.md) | [2026-11-23](async-primitives/README.md#2026-11-23-x86-64-linux-sandbox-4-cores-release-ms) |
| [`promise-tree`](promise-tree) | promise fan-out and one-promise-per-call fork trees at 1 and 4 threads | `MS_THREADS=4 ms run bench/perf/promise-tree/main.ms -- tree 36 5` | [`promise-tree/README.md`](promise-tree/README.md) |
| [`wait-all`](wait-all) | large pending promise fan-in, jitter and immediate-work controls | see the [protocol](wait-all/README.md) | [2026-11-07](wait-all/README.md#2026-11-07) |
| [`pure-utilities`](pure-utilities) | POSIX path and URL codecs against the recorded C and Rust controls, many runs, median | see the [protocol](pure-utilities/README.md) | [`pure-utilities/README.md`](pure-utilities/README.md) |
| [`strappend`](strappend) | `StringBuilder.append` and `List.append` growth against Rust | `make perf GROUP=strappend` | [`strappend/README.md`](strappend/README.md) |
| [`listloops`](listloops) | plain list loops must keep vectorizing, against C | `make perf GROUP=listloops` (also a release job) | [`listloops/README.md`](listloops/README.md) |
| [`competence`](competence) | fourteen competence kernels (calls, dispatch, closures, sort, text, maps, errors) against Go | `make perf GROUP=competence` | [`competence/README.md`](competence/README.md) |
| [`platform-io`](../tools/platform_io.ms) | file, spawn and pipe timings per platform against Rust | `make perf GROUP=platform-io`; the `Platform benchmarks` workflow runs it on all three platforms | the workflow artifact |
| [`compile-time`](compile-time) | generated-project build time against Go and Rust | `make perf GROUP=compile-time` | [`compile-time/results.md`](compile-time/results.md) |
| [`language`](language) | small language-level programs (calls, lists, numeric, life), two compilers | `make perf GROUP=language` | the command's output; sources are the conformance fixtures' origins |
| [`lists`](lists) | list storage program, native wall time and peak RSS | `make perf GROUP=lists` | the command's output; sources are the conformance fixtures' origins |
| [`lowering`](lowering) | lowering benchmark programs (`program`, `production`, `native-defaults`) | read the sources | [`lowering/program.ms`](lowering/program.ms) |

Compare numbers only from the same machine; treat them as a profiling guide, not a pass/fail gate.

The Manuscript programs use the native Rust/Cranelift `ms`. The Go and Rust
baselines require separate `go` and `rustc` installations; kernels also need a C
compiler. Set `MS` and `GO` explicitly because the scripts retain legacy default
paths. The program comparison allows normal inlining and reports medians with
alternating execution order. Every sample must
produce the expected operation counts and checksum. To retain the input, binaries,
environment, and raw samples for inspection:

```sh
MS=.artifacts/build/release/src/cli/ms GO=go BENCH_OUTPUT=.artifacts/perf-programs ms run bench/perf/tools/programs.ms -- 11
python3 -m unittest discover -s bench/perf/programs -p 'test_*.py'
```

## One suite

Every group has a row above and in [`groups.txt`](groups.txt); `make perf-check` fails on a path under `bench/perf/` that is neither a group's directory or page nor `README.md`, `groups.txt` or `results.md`. Numbers go in [`results.md`](results.md) (one section per group, newest run first) or the group's own protocol page. A finished investigation is deleted when its findings are in the wiki; the [index of deleted investigations](../../design/wiki/benchmarks-and-performance/deleted-perf-investigations-and-where-to-find-them.md) lists each with a permalink. Benchmarks of the deleted Rust implementation (`binding-flags`, `formatter-flow`, `lsp*`, `parser-*`) are in the same index.

## How performance is measured

- **Wall time:** each runner builds every language's program, runs it N times (rotating the order), and reports the minimum (`suite`, `kernels`, `competence`) or median (`programs`, `datastructures`) in ms, us or ns per operation. Process start and output are included, compilation is not. Every sample's output or checksum is compared with the reference (Rust, or Go where Rust has no equivalent) before a number is shown. Compare only runs from one machine.
- **Instruction counts:** shared VMs are noisy, so `make perf-counts` (group `guards`) runs the programs under callgrind and fails on a rise over 3% against [`counts.txt`](counts.txt). Nightly on `main`; use it for any perf change.
- **Allocation and copy counts:** `ms bench` blocks (`stdlib`, `guards/baseline.json`) record per-operation cost and allocations; the nightly `bench-gate` fails on a 3% rise.
- **Controls:** Rust is `rustc -O -C overflow-checks=on`, C is checked C, Go is `go build`; Node for JSON and the suite.

## Where the programs are

All benchmark sources and drivers are under `bench/perf/` (`tools/` holds the runners and `perf.ms`). Two things are shared on purpose: the `workloads` group runs ten agent-challenge reference solutions from `bench/agent/challenges/*/solutions`, which the agent benchmark also needs, and `tools/perf-counts.ms` stays in `tools/` with the other repository gates. Conformance fixtures under `tests/conformance/fixtures/bench/` are copies of some benchmark programs, kept to prove they compile; they are not measurements.
