+++
title = "Go lowering"
weight = 2
+++

# Go lowering

Lowering translates checked Manuscript into Go. The generated code must preserve evaluation order, closure captures, concurrency, and block-level cleanup. These pages describe how the compiler carries those guarantees across the translation.

## Structured Go generation

`pkg/lower/lower_*.go` consumes checked identities and the optimization view,
returning Go `ast.Expr` nodes and ordered `[]ast.Stmt` bodies. Function literals,
declarations, and the complete `ast.File` are assembled directly; lowering never
parses generated snippets. Small builders in `go_ast.go` express recurring Go
syntax without introducing another language IR. Identifiers come from checked
bindings or compiler-owned names, and source strings become quoted basic literals.
The Go printer owns operator precedence and spelling.

`print_go.go` is the source serialization boundary. It calls `format.Node` once,
then materializes source directives. Go statements have no attached-comment slot,
so lowering anchors each directive with a private label and records its source
position separately. The printer replaces each entire label line with a
column-one `//line` directive and checks that every marker was printed exactly
once. These markers use a separate counter from generated local names. Nested
closures, default arguments, actual loop labels, and generated fallback returns
retain their own locations. Runtime `SourceAt` and `TraceSource` calls remain
ordinary AST nodes with the same operand evaluation order.

Lowering should erase high-level abstractions when checked facts establish an
equivalent concrete Go representation. Building AST nodes alone does not make
native programs faster. This first migration preserves executable structure so
representation changes can be reviewed and measured separately. Checked
optimization facts, typed numeric operations, direct collection calls, and
ordered source-call preparation remain in place; Go optimizes the emitted native
operations.

Generated Go need not be readable or idiomatic. Prefer measured execution speed,
concrete representations, static dispatch, unboxed temporaries, and direct
control flow when they preserve Manuscript semantics and source mapping. Keep
the compiler implementation maintainable even when its output is mechanical.
Unsafe or runtime-internal techniques require explicit invariant evidence and
targeted tests; supported-platform and ABI guarantees still apply. Do not assume
Go will eliminate the overhead of generic runtime abstractions on its own.

The public `Result.Source` and native build/cache interfaces still accept printed
Go. `Standalone` separately parses complete generated and embedded runtime files
to combine them, and debugger path rebinding operates on final line directives.
Those existing output consumers are outside expression and statement lowering.

The compiler's `testdata/go-ast` fixture retains source and generated Go from
commit `9f3ffcee`, before AST lowering. Its differential test compares source
directives, then builds and executes both forms. Eligibility tests separately
check the executable AST shapes changed by production optimizations.
Do not refresh this independent baseline just because output formatting changes.

## Measure representation choices

From the checkout root, run:

```sh
toolchain/go/bin/go run ./scripts/bench-lowering -count=5
```

The command retains current generated Go and a handwritten Go comparison under
`.artifacts/lowering-bench/`, checks their results, and benchmarks scalar loops,
ordered source calls, and `List.at(...).unwrap()` loops. The handwritten versions
change scalar locals to `int64` while retaining the `Value` ABI, real source-call
callee, function wrappers, checked arithmetic, fault positions, cancellation,
cleanup defers, collection storage, and Optional operations. This isolates local
representation from dropping language guarantees. Inspect `program.go` beside
`program_test.go`; neither compilation nor process startup is in the benchmark
loop. Use a quiet machine for time comparisons, and report allocations as well.

Concrete scalar storage and known source calls now use native representations
at eligible boundaries. See [native scalar storage and calls](native-scalar-calls.md)
for storage classification, first-class adapters, default preparation, source
guards and compatibility. Dynamic aggregates and generic values still cross the
shared Value boundary; collection representation has its own runtime authority.

Two bounded production optimizations use checked facts while keeping the shared
representation and callable ABI:

- Equality lowers directly only for matching checked built-in `Int`, `Float`,
  `Bool`, and `String` primitive identities
  whose runtime comparison agrees with Go. Source implementations cannot replace
  primitive equality. Keep generic operands, contract views, nominal data,
  Decimal, and time values on their existing paths. Capture both operands once in
  source order, then update the operation's fault site; preserve Float NaN and
  signed-zero behavior. Test side-effecting operands, shadowed type names, and
  local/custom implementations alongside a primitive-equality benchmark.
- A source function's cleanup stack is omitted only when lowering emits no `with`
  registration owned by that function. Track actual use while building its AST;
  defaults and generated match closures share the owning stack, while nested
  source functions/closures make independent decisions. An empty `Unwind` only
  recovers and rethrows; retain source tracing, source-return/propagation wrappers,
  profiling, and cancellation. Test functions with and without cleanup across
  return, fault, cancellation, match exits, and nested closures, and measure the
  call benchmark with the same ABI before and after.

Run `toolchain/go/bin/go run ./scripts/bench-lowering -production -count=5`
to retain and measure the actual generated code. It covers an empty callable, a
callable that must keep cleanup, and 1,024-comparison loops for all four primitive
types. The equality loops retain a `with` registration to distinguish the hot
comparison from empty-stack omission. Results, IEEE behavior and cancellation
are checked before benchmarking. Compare baseline and candidate builds with the
same runtime/toolchain, alternating unprofiled samples on a quiet host; report
allocation counts and timing variability rather than extrapolating to a workload
that was not reproduced.

The workload harness adds complete loop, call, access and Game of Life checks:

```sh
toolchain/go/bin/go run ./scripts/bench-lowering -workloads -count=5
```

Retain main and candidate generated sources and raw allocation samples. Keep
identity, forwarding, capture and storage controls alongside hot loops: removing
one box at a numerical boundary can add a replacement at another boundary.
List storage, immediate Optional consumption and comparator dispatch must be
validated together with their authoritative runtime representation. Mutable
aliasing, shallow cloning, recursive data, nominal identity and local
implementation scopes remain source contracts.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
