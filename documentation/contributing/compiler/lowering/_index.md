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
