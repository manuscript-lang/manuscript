+++
title = "Go lowering"
weight = 2
+++

# Go lowering

Lowering translates checked Manuscript into Go while preserving evaluation order, closure captures, concurrency, and block-level cleanup.

## Typed Go

Every Manuscript type lowers to exactly one Go type, so the Go compiler sees hand-written-style code: `Int` is `int`, a record is a struct pointer, `List[T]` is `*rt.List[T]`, a function is `func(*rt.Execution, A...) R`. There is no universal value type, boxing, or `any` in generated signatures. [Go representation](../../go-lowering-representation.md) states the reference-or-value rule.

- `pkg/lower` consumes checked identities and returns Go `ast` nodes (expressions, statement lists, declarations, a whole `ast.File`). It never parses generated snippets.
- One printer boundary (`print_go.go`) formats the tree once and materializes source directives.
- The runtime, `pkg/runtime`, is imported as `rt`; `Standalone` merges it into one file for `ms emit`.
- Lowering runs in independent [units](../../go-lowering-units.md), one per function instance.

## Source locations and fault frames

- Each located Go statement carries a private label. The printer swaps it for a column-one `//line` directive and checks each marker prints exactly once. Multi-line statements repeat it in `/*line*/` form where a call can sit, and every top-level declaration starts with `//line generated.go:1` so glue never inherits a source line.
- Source functions carry no per-call bookkeeping. A fault captures frames once, where raised, from the Go stack: `RegisterSource` and `rt.Named` map functions to source names (`test <name>`, `<anonymous>`) and directives supply file and line. Each lambda owns a package-level `rt.Site`.
- Only functions in a recursive cycle call `Enter`/`Exit`; depth limit and cancellation are sampled every 256th entry.

## Defaults belong to the callee

- A defaulted parameter is `rt.Arg[T]{Val, Set}` in source functions, lambdas, methods, and function types. The callee prologue binds the value or evaluates the default in its own scope, so defaults can read earlier parameters and `try` returns from the callee. Calls pass `rt.Given(v)` or `rt.Arg[T]{}`.
- Native functions, record constructors, and runtime contracts keep plain parameters; call sites evaluate their defaults.
- A function value with differing defaults is adapted by a wrapper (`convertFunction`). Generic record field defaults lower at the construction site with type arguments substituted.

## Equality and keys

- Types whose Go equality is Manuscript equality (scalars, strings, `Duration`, `Timestamp`, handles, `Unit`) use `==` and key a `Map` or `Set` directly.
- Everything else gets generated `equal_T`, `format_T`, and `key_T` (a projection to a comparable `[N]any`). Explicit `Equal` or `Hashable` implementations use `rt.CustomKeys(hash, equal)`, whose closures capture the constructing execution.
- A `Map` or `Set` keeps the `*rt.Keys[K]` it was built with, so **a collection matches keys with the equality of the module that created it**.
- Possibly cyclic structural equality is guarded by `rt.EnterEqual`/`LeaveEqual`.

## Implementation scope

Implementations are visible only in their declaring module. A generic instantiated from another module resolves its type variables' contract operations against the instantiating module first (`g.scope`, a comma-separated module chain), then its own. The instance key and generated name include that scope, as do views, `equal_`, and `key_` helpers when any module declares a local implementation (`localImpl`). In that case a `match` on a contract value switches on `rt.ReceiverOf`.

## Measure representation choices

From the checkout root with the pinned SDK:

```sh
toolchain/go/bin/go run ./bench/lowering -count=5
```

Compare against handwritten Go with the same checked arithmetic, fault positions, cancellation, and cleanup. Report allocations and time on a quiet machine, alternating unprofiled samples. Claim no speedup you did not reproduce.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)


## Local arithmetic proofs

Release lowering can remove an Int arithmetic check only when exact interval
arithmetic proves every result fits. Facts belong to checked bindings in one
callable; unknown control flow discards them. Finite unit-step loops bound every
prefix of each accumulator using separate positive and negative budgets. All
modified scalar, list and record facts become unknown before deriving any new
invariant, so another accumulator's initial value cannot justify a check removal.

An exhaustive use inventory permits bounds for fresh private Int lists and
one-field Int records. Aliases, captures, unsupported mutations and calls retain
the checked path. Record specialization also falls back inside generic callers.
List access still performs its ordinary index/default checks;
only a proved length becomes constant. Debug retains the source bindings and
checked operations. Closed Int maps use the exclusive helpers described in
[Go representation](../../go-lowering-representation.md#closed-local-int-maps).

Only a finite ascending loop with two safe scalar updates, a constant independent
stride, a last counter step, and at least 256 iterations may group its polling
control. Each original assignment still executes individually. Queries occur
before exactly the same 64th, 128th, and subsequent iterations; partial tails
and signed endpoints retain that phase.

An exact adjacent `let value = try result; return ok(value)` can return the
original Result when payload and error types agree without conversion. Other
`try` expressions still evaluate once, test failure and return the error. Function
payloads retain their calling-convention conversion path.

A Bool tail that only asks whether canonical `read_line` succeeded with a present
line can omit materializing its unused String. The runtime shares the ordinary
algorithm and retains validation, limits, locking, consumption, errors and
cancellation queries. Text-returning reads and other source shapes are unchanged.
