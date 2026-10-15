+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

`pkg/rt` is the runtime generated Go programs link against. Every standard native operation has one Go function whose signature the lowerer calls directly: no `any`, no interface-typed values, no boxing.

## The contract is generated

`golowerdev stdgen pkg/rt` writes two kinds of files from the `.ms` declarations:

- `std_types_gen.go` always builds. It declares the standard records, sum types (`Name_Case` structs behind a sealed interface), and contracts (Go interfaces).
- `std_<module>_gen.go` builds only with `-tags rtcheck`. Each `check_*` function pins one native function, operation, or implementation to the exact Go signature the lowerer calls. `go build -tags rtcheck -gcflags=-e ./pkg/rt 2>&1 | grep std_<module>_gen.go` lists what a module still lacks. When it is empty the module is complete.

Never edit generated files. A signature that looks wrong is a lowerer or declaration issue: report it, do not work around it.

## Naming and shape

- Functions are `Module_Function` or `Type_Method` as the check shows, for example `List_Contains`, `Errors_Message_FileSystemError`, `Collections_Range`.
- Every function takes `ctx *Execution` first. A capability follows it: `Eq[T]` is the equality of `T` when the declaration bounds `T: Equal`. Hashable needs no argument; map and set keys are Go `comparable`.
- The receiver follows the capabilities, then the declared parameters in order. Type arguments are Go type parameters in declaration order.
- Fallible operations return `Result[T, E]` with the generated error sum type. Never panic for an expected failure; use `Raise(message)` only for programming faults the declaration documents as faults.
- Long-running operations call `CheckCancelled(ctx)` and honor `ctx.Context`. Blocking calls select on `ctx.Context.Done()`.
- Constructors of native types are `New<Type>`. Native types that are handles are pointers; `Duration`, `Instant` and `Timestamp` are values.
- Contract values (`Files`, `Clock`, ...) are Go interfaces. Provide concrete types and a `var _ Files = (*osFiles)(nil)` assertion.
- Strings are Go strings (UTF-8); `Int` is `int64`; `List[T]` is `*List[T]` with an `Items` slice; `Map` and `Set` preserve insertion order.

## Representation

Reference vs value rules are in [Go representation](go-lowering-representation.md). Records and collections are shared by aliases; `Option`, `Result`, alternatives and contracts are values.

## Porting from the old runtime

`pkg/runtime` holds the previous `Value`-based implementation. Port its behavior, error cases, and messages exactly, and its tests where they exercise language-visible behavior. Do not import `pkg/runtime` from `pkg/rt`. The old runtime will be deleted when the compiler switches.

## Ownership

Each module owns its `pkg/rt/<module>*.go` files and their tests. Shared files (`core.go`, `exec.go`, `fault.go`, `list.go`, `map.go`, `set.go`, `numeric.go`) belong to the runtime core. Add what you need in your own files. If a shared file must change, make the smallest edit and say so in your report.

## Verifying

- `go build ./pkg/rt && go vet ./pkg/rt`
- `go build -tags rtcheck -gcflags=-e ./pkg/rt` shows no errors in your `std_*_gen.go` files.
- `go test ./pkg/rt` passes with `-race` for concurrent code.
- End to end, `golowerdev FILE test` lowers and runs a Manuscript file against `pkg/rt` (build it with `go build -o /tmp/golowerdev ./cmd/golowerdev`); use fixtures from `tests/e2e/testdata/stdlib` that touch only your modules.
