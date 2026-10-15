+++
title = "Go lowering"
weight = 2
+++

# Go lowering

Lowering translates checked Manuscript into Go. The generated code must preserve evaluation order, closure captures, concurrency, and block-level cleanup. These pages describe how the compiler carries those guarantees across the translation.

## Typed Go

Every Manuscript type lowers to exactly one Go type, so a Go compiler sees the program a person would write by hand: `Int` is `int64`, a record is a pointer to a struct, a `List[T]` is `*rt.List[T]`, a function is `func(*rt.Execution, A...) R`. There is no universal value type, no boxing, and no `any` in a generated signature. [Go representation](../../go-lowering-representation.md) states the reference-or-value rule; this page covers how the lowerer keeps the guarantees Go does not.

`pkg/lower` consumes checked identities and returns Go `ast` nodes: expressions, ordered statement lists, declarations, and a whole `ast.File`. It never parses generated snippets. One printer boundary (`print_go.go`) formats the tree once and then materializes source directives. The runtime, `pkg/runtime`, is imported as `rt`; `Standalone` merges it into one file for `ms emit`.

Lowering works in independent [units](../../go-lowering-units.md), one per function instance, so it scales with cores and a change stays local.

## Source locations and fault frames

Go statements have no attached-comment slot, so each located statement carries a private label. The printer replaces the label with a column-one `//line` directive and checks that every marker printed exactly once. A statement that prints over several Go lines repeats its directive in `/*line*/` form on lines that can hold a call. Every generated top-level declaration starts with `//line generated.go:1`, so helper functions and runtime glue never inherit a source line.

Source functions carry no per-call bookkeeping. A fault captures its frames once, where it is raised, from the Go stack: `RegisterSource` and `rt.Named` map each generated function to its source name (a test shows as `test <name>`, a lambda as `<anonymous>`), and the directives supply file and line. Each lambda expression owns a package-level `rt.Site`, so naming costs one atomic load after the first evaluation. Only functions in a recursive call cycle call `Enter`/`Exit` to count depth; the limit and cancellation are sampled every 256th entry.

## Defaults belong to the callee

A parameter that declares a default is an `rt.Arg[T]{Val, Set}` in the Go signature of source functions, lambdas, methods, and function types. The callee's prologue binds the supplied value or evaluates the default in its own scope, so a default may read earlier parameters and `try` returns from the callee. Call sites pass `rt.Given(v)` or `rt.Arg[T]{}`. Native functions, record constructors, and standard (runtime) contracts keep plain parameters; the call site evaluates their defaults. A function value whose defaulted parameters differ from the type it is used as is adapted with a small wrapper (`convertFunction`). Field defaults of a generic record are lowered at the construction site with the record's type arguments substituted.

## Equality and keys

Types whose Go equality is their Manuscript equality (scalars, strings, `Duration`, `Timestamp`, handles, `Unit`) compare with `==` and key a `Map` or `Set` directly. Everything else gets generated helpers: `equal_T`, `format_T`, and `key_T`, a projection to a comparable `[N]any` array. An explicit `impl Equal` or `Hashable` is honored through `rt.CustomKeys(hash, equal)`, whose closures capture the constructing execution.

A `Map` or `Set` is built with an `*rt.Keys[K]` and keeps it for its lifetime, so **a collection matches keys with the equality of the module that created it**; a bound operation obtained from another module does not change that. Structural equality of data that can reach itself is guarded by `rt.EnterEqual`/`LeaveEqual` so cyclic values terminate.

## Implementation scope

Implementations declared in one module are visible only there. A generic function or method instantiated from another module resolves the contract operations of its type variables against the instantiating module first (`g.scope`, a comma-separated chain of modules), then its own. The instance key and generated name include that scope, and so do views, `equal_`, and `key_` helpers when any module declares a local implementation (`localImpl`). With local implementations, a `match` on a contract value switches on `rt.ReceiverOf` so a value wrapped by one module's view still matches in another.

## Measure representation choices

Run the benchmarks from the checkout root with the pinned SDK:

```sh
toolchain/go/bin/go run ./scripts/bench-lowering -count=5
```

Compare generated Go to a handwritten equivalent with the same checked arithmetic, fault positions, cancellation, and cleanup. Report allocations as well as time, use a quiet machine, and alternate unprofiled samples when comparing builds. Do not claim a speedup for a workload that was not reproduced.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
