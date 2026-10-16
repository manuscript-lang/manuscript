+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

`pkg/runtime` (package `msruntime`, imported by generated code as `rt`) is the runtime generated Go programs link against. Every standard native operation has one Go function whose signature the lowerer calls directly: no `any`, no interface-typed values, no boxing.

## The contract is generated

`make stdgen` (`go run ./scripts/stdgen pkg/runtime`) writes two kinds of files from the `@std` declarations in `pkg/stdlib/*.ms`:

- `std_types_gen.go` always builds. It declares the standard records, sum types (`Name_Case` structs behind a sealed interface), and contracts (Go interfaces).
- `std_<module>_gen.go` builds only with `-tags rtcheck`. Each `check_*` function pins one native function, operation, or implementation to the exact Go signature the lowerer calls. `go build -tags rtcheck -gcflags=-e ./pkg/runtime 2>&1 | grep std_<module>_gen.go` lists what a module still lacks. When it is empty the module is complete.

The lowering package's `TestGeneratedRuntimeIsFresh` fails while the checked-in files differ from the generator. Never edit generated files; a signature that looks wrong is a declaration or lowerer issue.

## Naming and shape

- Functions are `Module_Function` or `Type_Method` as the check shows, for example `List_Contains`, `Errors_Message_FileSystemError`, `Collections_Range`.
- Every function takes `ctx *Execution` first. A capability follows it: `keys *Keys[T]` when the declaration bounds `T: Hashable`, and `Eq[T]` when it bounds `T: Equal`.
- The receiver follows the capabilities, then the declared parameters in order. Type arguments are Go type parameters in declaration order.
- Native functions, record constructors, and standard contracts take plain parameters; callers evaluate declared defaults. Source functions take `Arg[T]` for defaulted parameters (see [Go representation](go-lowering-representation.md)).
- Fallible operations return `Result[T, E]` with the generated error sum type. Never panic for an expected failure; use `Raise(message)` only for programming faults the declaration documents as faults.
- Standard error cases implement `Categorized`; `Errors_Category` reads it, or the `Receiver()` of a contract view.
- Long-running operations call `CheckCancelled(ctx)` and honor `ctx.Context`. Blocking calls select on `ctx.Context.Done()`.
- Constructors of native types are `New<Type>`. Native types that are handles are pointers; `Duration`, `Instant` and `Timestamp` are values.
- Contract values (`Files`, `Clock`, ...) are Go interfaces. Provide concrete types and a `var _ Files = (*osFiles)(nil)` assertion.
- Strings are Go strings (UTF-8); `Int` is Go `int` (platform-sized); host values that are always 64-bit, such as `Duration` nanoseconds, stay `int64` and convert with `FitInt` or `clampInt`; `List[T]` is `*List[T]` with an `Items` slice; `Map` and `Set` preserve insertion order and match keys with their `*Keys[K]`.

## Representation

Reference vs value rules are in [Go representation](go-lowering-representation.md). Records and collections are shared by aliases; `Option`, `Result`, alternatives and contracts are values.

## Build inputs

`msruntime.Sources` is the set of files a program builds with: every non-test `.go` file except `bundle.go`. It feeds pin identity, the shared native workspace, and `Standalone` bundles. Keep one import alias per path across files, because bundling folds the files into one.

## Verifying

- `go build ./pkg/runtime && go vet ./pkg/runtime`
- `go build -tags rtcheck -gcflags=-e ./pkg/runtime` shows no errors in `std_*_gen.go`.
- `go test ./pkg/runtime` passes with `-race` for concurrent code.
- End to end, run fixtures from `tests/e2e/testdata/stdlib` with `make stdlib-test` and the e2e suite with `make e2e`.
