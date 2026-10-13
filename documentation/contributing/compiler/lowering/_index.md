+++
title = "Go lowering"
weight = 2
+++

# Go lowering

Lowering translates checked Manuscript into Go. The generated code must preserve evaluation order, closure captures, concurrency, and block-level cleanup. These pages describe how the compiler carries those guarantees across the translation.

## Structured Go generation

`pkg/compiler/lower_*.go` consumes checked identities and the optimization view,
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

The public `Result.Source` and native build/cache interfaces still accept printed
Go. `Standalone` separately parses complete generated and embedded runtime files
to combine them, and debugger path rebinding operates on final line directives.
Those existing output consumers are outside expression and statement lowering.

The compiler's `testdata/go-ast` fixture retains source and generated Go from
commit `4d9bce1f`, before AST lowering. Its differential test compares parsed
executable structure and source directives, then builds and executes both forms.
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

Current generated loops still store primitive locals as `rt.Value`, extract them
for arithmetic, and box results again on assignment. Ordered source calls avoid
label preparation but still pass `[]rt.Value` through `Function.Body`. Lists store
`[]rt.Value`, and `.at().unwrap()` still creates and consumes an ordinary Optional
alternative. Generic specialization, contract dispatch, and closure snapshots
also cross the shared value boundary.

The next specialization should start with noncaptured concrete scalar locals
whose repeated uses remain in arithmetic or comparisons, converting at explicit
boundaries. Do not change every concrete local blindly: in the benchmark's call
loop, unboxing a returned value and boxing it again for the next call adds
allocations. Keep those locals boxed until a separately measured typed-call path
can remove both conversions. Preserve checked overflow, Float rounding, operand
order, source frames, cancellation, and debugger-visible names.

Subsequent candidates are typed entry points for eligible known source functions
with adapters at callable/generic boundaries, and fusion of an immediately
consumed Optional where no alternative escapes. They need separate evidence for
defaults, recursion, callbacks, error propagation, profiling, negative indexing,
absent values, and fault sites. Aggregate layout changes are a later stage:
mutable aliasing, shallow cloning, recursive data, nominal identity, and local
implementation scopes prevent replacing every record or collection with an
unqualified Go value. No language semantics or ABI change is implied by these
benchmark candidates.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
