# Checker efficiency pass, 2026-10-18

This pass owns `pkg/checker` only. It retains the checked source tree and every semantic pass. It changes two bounded sources of repeated work:

* `Fields` and `Cases` now bind a nominal application's type arguments once per query rather than once per payload field, and allocate their result slices once. Substitution still returns supplied argument pointers and copies other type structure. Empty results retain nil slices. Binding is lazy for alternatives without payloads.
* Effect propagation indexes callers and revisits only callers of a changed effect set, instead of scanning every graph edge until convergence. Missing callees remain unknown, cycles converge, and effect names remain sorted. The scanner for closures, defaults, implicit cleanup, and ordinary calls is unchanged. An entirely pure graph exits before allocating the reverse index.

No persistent type cache, second tree, runtime representation, dependencies, or external Go/dlv runtime requirements were added. Native output is unchanged for the compared fixture corpus.

## Revisions and environment

* Initial current main: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
* Integrated main for final measurements: `7f5834b2129b02e3c7cc1597514f8e34e04b1006` (PRs #659 and #660 arrived during the pass).
* Baseline with the identical benchmark source: local `985bdad3ea988aae720c41b8c1bc5b18665dc543`, equivalent to that integrated main plus `performance_test.go`.
* Measured candidate: `5820837b26604b9af2431deca9cf0e4ffad9d7e8`.
* Production commits: `33165423` (specialization) and `176875a8` (effects). Benchmark commits: `9535be73`, `3d1a0925`.
* Benchmark source SHA-256: `f4118906de1a3dbe9c5d6fd1875dba69fc46bfc6cfb8ec0178f7c67bca1ce016`.
* Go 1.25.1, linux/amd64, default compiler/GC, CGO enabled, no GOEXPERIMENT. SDK downloaded and checksum verified using the repository's bootstrap script. Linux 6.18.55; Intel Xeon Platinum 8573C; five visible logical CPUs with a four-CPU cgroup quota; 16 GiB memory limit. Benchmark execution uses one Go CPU.
* Five paired samples, alternating separate before/after test processes, 200 ms per benchmark sample. No other agent tests or native builds ran during sampling. Shared virtual machine scheduling and CPU frequency remain uncontrolled.

The primary workloads parse a fresh tree and check it on every iteration, with standard declarations warmed before timing. The timings include parsing, all semantic checks, and effect summaries; they exclude native code generation/build and first-process standard loading. Microbenchmarks isolate field/case specialization. `before.txt` and `after.txt` retain raw samples; `summary.csv` retains medians and observed ranges. These small samples establish large changes and controls, not precise significance for small timing differences.

## Measured results

Medians of five paired samples; MB below means decimal bytes. Whole-check workloads include parsing.

| Workload | Before | After | Allocated bytes before → after | Allocations before → after |
| --- | ---: | ---: | ---: | ---: |
| Effect chain, 128 functions | 3.306 ms | 1.659 ms | 1.346 → 1.361 MB | 9,634 → 9,767 |
| Effect chain, 256 functions | 9.774 ms | 3.569 ms | 3.297 → 3.327 MB | 19,183 → 19,443 |
| Effect chain, 512 functions | 33.482 ms | 7.083 ms | 6.311 → 6.375 MB | 38,394 → 38,910 |
| Recursive effect cycle, 512 functions | 33.774 ms | 7.554 ms | 6.314 → 6.378 MB | 38,419 → 38,936 |
| Generic record, 16 parameters/fields and 16 reads | 0.718 ms | 0.236 ms | 0.521 → 0.187 MB | 2,302 → 1,044 |
| Generic record, 32 parameters/fields and 32 reads | 4.656 ms | 0.526 ms | 3.627 → 0.425 MB | 8,924 → 1,825 |
| Generic record, 64 parameters/fields and 64 reads | 35.087 ms | 1.453 ms | 28.336 → 1.236 MB | 40,096 → 3,423 |
| `Fields`, 128 parameters/fields | 2.122 ms | 0.019 ms | 1.704 → 0.016 MB | 1,416 → 12 |
| `Cases`, 128 parameters/payload fields | 2.097 ms | 0.020 ms | 1.704 → 0.017 MB | 1,417 → 13 |

The effect chain goes from roughly 3x time per doubling to roughly 2x; the wide-record workload still performs N field queries of width N, but removes another per-field binding factor. This is not a claim that every checker workload becomes linear.

Negative controls are retained without suppressing regressions:

* Pure connected chain, 512: 6.742 → 6.904 ms (+2.4%); 37,363 allocations on both sides. Disconnected pure functions, 512: 4.860 → 4.776 ms. At 128 disconnected functions the after median is +6.4%, with ranges 1.142–1.202 ms before versus 1.154–1.727 ms after; no speedup claimed.
* Many callers of one callee, 256: 3.482 → 3.682 ms (+5.7%); ranges 3.425–3.581 versus 3.525–3.793 ms overlap. Reverse indexing adds 36.9 KB/op. At 512 functions the median delta is +1.4%.
* Repeated ordinary generic calls, 512: 7.625 → 7.369 ms, with 6.299 → 6.143 MB and 39,997 → 37,437 allocations. Nongeneric field and empty phantom-case microbenchmarks keep exactly 184 B/2 allocations and 48 B/1 allocation respectively.
* Existing nested map literal: 2.144 → 2.280 ms (+6.3%), unchanged 1,491,693 B and 10,251 allocations. Nested list literal: 4.837 → 4.884 ms (+1.0%), unchanged allocation count. These remain controls for already-shipped work, with no improvement claimed.

The worklist intentionally adds temporary O(V+E) storage on effectful graphs. For the 512-function chain this is +63,547 B/op (+1.0%) and +516 allocations (+1.3%), in exchange for -78.8% time. In three fresh-process, fixed-ten-iteration samples, chain peak RSS was 22,200–24,904 KiB before and 26,756–28,932 KiB after; wide-record RSS was 24,836–26,720 versus 22,532–23,940 KiB. Pure-chain samples ranged 21,704–27,860 versus 21,508–26,184 KiB. Peak RSS includes GC timing, startup, stacks and resident code and is too noisy here to infer retained-tree size. Raw samples are in `memory.csv`; the peak increase on the effectful chain is a recorded cost, not hidden by the allocation result.

Separate two-second CPU profiles confirm the targeted work: `propagateEffects` accounts for 77.5% cumulative CPU on the baseline chain. The baseline wide-record profile spends 87.8% cumulative CPU in map assignment; the candidate removes repeated binding maps. The four `*-cpu.txt` files retain flat and cumulative profile summaries. CPU shares are relative to different iteration counts and must not be interpreted as absolute speed ratios.

## Unresolved efficiency findings

`finiteApplications` still re-walks generic call paths from each generic root without a shared completed-specialization memo. A diamond where each layer calls the preceding generic function twice takes 0.411/1.018/3.272 ms at 8/10/12 layers before, and 0.409/1.030/3.302 ms after. Its 2,212/5,526/18,054 allocation counts are identical before and after. This path needs a separate recursion-semantics argument: a memo must preserve active-path cycle checks and diagnostics, so this pass does not introduce a speculative visited set. Existing type-declaration recursion already has the #490 optimization and remains unchanged.

Other inspected surfaces have no isolated improvement established here. In particular, repeated resolver calls may intentionally refresh implementation bounds and source facts; general memoization is not justified by these measurements. The package has measured improvements, not an exhaustive proof that every possible adversarial workload is efficient.

## Coverage matrix

Every production Go file in this package was inventoried. Inspection does not mean every path was independently profiled or optimized.

| Files | Evidence and disposition |
| --- | --- |
| `types.go` | Wide generic records and direct field/case specialization at 16/32/64/128 fields; improved repeated binding. `Sub`, `Same`, defaults, bounds, type identity and required-type behavior retained. |
| `effects.go` | Effectful chain, recursive cycle, many callers of one callee, disconnected pure nodes, and connected pure chains at 128/256/512 functions. Improved propagation; extra temporary O(V+E) memory for effectful graphs measured. Independent reachability oracle tests arbitrary effect sets. |
| `recursion.go`, `type_recursion.go` | Generic call diamond at levels 8/10/12, existing type diamonds and recursive-type acceptance/rejection tests. Type recursion already shares specialization visits (#490). Generic call recursion still repeats paths; recorded as unresolved below. |
| `checker.go`, `expressions.go`, `calls.go`, `inference.go`, `callbacks.go`, `contracts.go`, `native_members.go` | Repeated generic calls, wide member lookup, existing nested list/map/constructor scaling tests, complete checker tests and fixture equivalence. Already-delivered #606 avoids repeated nested inference and bounds walks. No new resolver, contract, method-index, or general substitution cache justified in this pass. |
| `standard.go`, `prelude.go`, `prelude_imports.go` | Existing first-use/lazy loading and concurrent reuse tests, race run, ordinary warm checking controls. Already shares standard annotated trees (#341). No cold-loading or retained-cache improvement claimed. |
| `bounds.go`, `mutation.go`, `constants.go`, `errors.go`, `inherent.go`, `test_fixture.go` | Static ownership trace plus full checker and downstream tests. Bounds invalidation, mutation/alias checks, constant cycles, inherent impl desugaring and fixture checks retained. No isolated performance improvement claimed. |
| `model.go`, `editor.go`, `pattern_names.go`, `pass_arguments.go`, `pass_fold.go`, `pass_try.go` | AST-preservation tests, expression-fact equivalence, downstream compiler/lowering/tooling tests. One annotated tree and complete checking of invalid/short-circuited operands retained. No change. |
| `documentation.go`, `documentation_members.go`, `documentation_syntax.go`, `primitive_documentation.go`, `hints.go`, `inference_hints.go`, `inventory.go`, `lowering_support.go`, `identity.go` | Static inspection and downstream documentation, hint, inspection and LSP tests. No speculative tooling caches or implementation-hash changes. No isolated improvement claimed. |

## Correctness and review

* Focused tests compare effect summaries with an independent reachability oracle across 100 deterministic graphs, including missing callees, cycles, multiple distinct effect sources, and repeat propagation. A pure recursive component remains pure.
* Specialization tests cover partial bindings, nested function parameters/results/default metadata, empty case payloads, nil result slices, sharing of bound argument pointers, independent copies of unbound structure, mutation of result slices, and later queries with changed arguments.
* Full checker, compiler, lowering, tooling (including docs, guide and LSP), and repo-check package tests pass on integrated main. Repository policy checks and relevant race tests pass. Existing tooling tests protect closure, transitive call, implicit cleanup and constructor-default effects.
* The retained `equivalence.go` harness compares emitted-Go hashes, sorted diagnostics, effect summaries and expression facts for all 108 root acceptance/rejection fixtures (106 acceptance, two rejection). The baseline was run twice as a determinism control; all three runs match exactly. Combined JSONL SHA-256: `f8e0214011ffb4b34329bc0715929ec737509507e788cc8803b5023cb1c962d4`. Broader rejection coverage comes from the complete checker tests, not these two root rejected files alone.
* Native `TestCoreConformance`, `TestRejectedFixture`, `TestFieldDefaultsAcrossModules`, `TestGenericRecordInstantiationsKeepSemantics`, `TestInherentImplDeclaresTypeMethods`, `TestErrorBoundariesPreserveLocalImplementations`, `TestEvaluationOrderAndEveryCleanupExit`, `TestMutationAliasesScopedImplementations`, `TestTypedNumericFaults`, and `TestStandaloneHasNoRuntimeDependency` pass (`-count=1`, 56.725 s). Development caches use writable task-specific `/tmp` locations (`XDG_CACHE_HOME`, `GOCACHE`, `GOMODCACHE`); an initial run without a writable application cache failed before native execution and was rerun with the correct environment.
* A separate sol reviewer challenged the proposal before implementation, checked the code and negative controls, and independently reran AST-preservation, specialization and effect integration tests. The negative controls caught an initial heap-map regression in ordinary generic calls; that version was corrected before final measurement.

## Reproduce

Use the pinned development SDK (`make toolchain`). No benchstat dependency is required to inspect the raw data or medians.

```sh
git worktree add --detach /tmp/checker-before 7f5834b2129b02e3c7cc1597514f8e34e04b1006
git show 5820837b26604b9af2431deca9cf0e4ffad9d7e8:pkg/checker/performance_test.go > /tmp/checker-before/pkg/checker/performance_test.go
```

Build a checker test binary in each checkout using the same SDK and flags, then alternate this command five times per binary:

```sh
checker.test -test.run '^$' -test.bench 'BenchmarkChecker|BenchmarkNested' -test.cpu=1 -test.benchmem -test.benchtime=200ms -test.count=1
```

Run the equivalence harness from each checkout root:

```sh
toolchain/go/bin/go run /absolute/path/to/equivalence.go > equivalence.jsonl
```

Process peak RSS measurements use a fresh test binary process, `-test.benchtime=10x`, and the kernel's child `ru_maxrss`. They include process startup and the once-warmed standard registry, and are not retained-tree heap measurements. Allocation totals in B/op include temporary data, not just live heap. Neither metric claims a reduction in cold standard-cache size. CPU profiles are sampled separately from timing runs.
