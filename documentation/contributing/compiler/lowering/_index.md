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

Current generated loops still store primitive locals as `rt.Value`, extract them
for arithmetic, and box results again on assignment. Ordered source calls avoid
label preparation but still pass `[]rt.Value` through `Function.Body`. Lists store
`[]rt.Value`, and `.at().unwrap()` still creates and consumes an ordinary Optional
alternative. Generic specialization, contract dispatch, and closure snapshots
also cross the shared value boundary.

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
- A source method of a nongeneric record or alternative is a direct Go function
  (`method_N`) taking its receiver after `ctx`, with typed scalar parameters and
  result like a top-level direct function. A call whose receiver has that exact
  checked type and supplies every argument in order calls it without runtime
  method resolution (`planDirectMethod`); views, generic receivers, defaults and
  reordered labels keep `CallMethod`. The implementation table still registers
  the method, so dynamic calls forward to the same function. Test receiver and
  argument order, `try` on a method result, and fault frame names.
- A `try` nested in a statement's value (`a + try f()`, `g(try f())`) is evaluated
  ahead of the statement with an early Go return, like a whole-statement `try`,
  when everything the statement evaluates before it is a literal, a name or an
  earlier `try` (`hoistTries`). Otherwise (short-circuit operands, earlier calls,
  closures, `match`) it keeps the panic form. Test failure order with side
  effects before and after each `try`.

Run `toolchain/go/bin/go run ./scripts/bench-lowering -production -count=5`
to retain and measure the actual generated code. It covers an empty callable, a
callable that must keep cleanup, and 1,024-comparison loops for all four primitive
types. The equality loops retain a `with` registration to distinguish the hot
comparison from empty-stack omission. Results, IEEE behavior and cancellation
are checked before benchmarking. Compare baseline and candidate builds with the
same runtime/toolchain, alternating unprofiled samples on a quiet host; report
allocation counts and timing variability rather than extrapolating to a workload
that was not reproduced.

Next, specialize noncaptured concrete scalar locals whose repeated uses remain
in arithmetic or comparisons, converting at explicit boundaries. Do not change
every concrete local blindly: in the benchmark's call loop, unboxing a returned
value and boxing it again for the next call adds allocations. Keep those locals
boxed until a separately measured typed-call path can remove both conversions.
Specialization hoisting must retain the exact checked type arguments and recursive
implementation scopes; matching type spellings alone do not establish reusable
dispatch. Preserve checked overflow, Float rounding, operand order, source frames,
cancellation, and debugger-visible names.

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
- A nongeneric top-level function whose checked result is `Result[T, E]` or
  `Optional[T]` returns the runtime's `Result[T]`/`Option[T]` (`T` a Go scalar
  or `Value`; the error cause stays a `Value`) instead of an `Alternative`.
  Only `return`, statement-level `try`, and `match` on a typed call produce or
  consume the typed form; every other consumer, including arguments, equality,
  formatting, first-class function values, and the dynamic wrapper, receives the
  boxed `Alternative` with the call's own type key, so nothing dynamic observes a
  typed value. Returns inside generated match closures stay boxed and are
  unboxed by the function's recovery path. Test display and equality parity,
  error views, closures that return, and `try` in nested positions, and measure
  the `try`/`match` benchmark before and after.
