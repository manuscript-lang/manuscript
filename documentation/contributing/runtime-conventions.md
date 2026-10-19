+++
title = "Typed runtime conventions"
weight = 22
+++

# Typed runtime conventions

`pkg/runtime` (package `msruntime`, imported as `rt`) is what generated Go links against. Each standard native operation is one Go function with a signature the lowerer calls directly: no `any`, interface-typed values, or boxing.

## The contract is generated

`make stdgen` (`go run ./scripts/stdgen pkg/runtime`) writes two file kinds from `@std` declarations in `pkg/stdlib/*.ms`:

- `std_types_gen.go` always builds. It declares standard records, sum types (`Name_Case` structs behind a sealed interface), and contracts (Go interfaces).
- `std_<module>_gen.go` builds only with `-tags rtcheck`. Each `check_*` function pins a native function, operation, or implementation to the exact signature the lowerer calls. `go build -tags rtcheck -gcflags=-e ./pkg/runtime 2>&1 | grep std_<module>_gen.go` lists what a module lacks; empty means complete.

`TestGeneratedRuntimeIsFresh` in the lowering package fails while checked-in files differ from the generator. Never edit generated files; a wrong-looking signature is a declaration or lowerer issue.

## Naming and shape

- Names are `Module_Function` or `Type_Method`, such as `List_Contains` or `Collections_Range`.
- Parameter order: `ctx *Execution`, capabilities (`keys *Keys[T]` for `T: Hashable`, `Eq[T]` for `T: Equal`), receiver, declared parameters. Type arguments are Go type parameters in declaration order.
- Native functions, record constructors, and contracts take plain parameters; callers evaluate defaults. Source functions take `Arg[T]` for defaulted parameters (see [Go representation](go-lowering-representation.md)).
- Fallible operations return `Result[T, E]` with the generated error sum type. Use `Raise(message)` only for documented programming faults.
- Standard error cases implement `Categorized`, read by `Errors_Category` or a contract view's `Receiver()`.
- Long-running operations call `CheckCancelled(ctx)`; blocking calls select on `ctx.Context.Done()`.
- Constructors are `New<Type>`. Handle types are pointers; `Duration`, `Instant`, and `Timestamp` are values.
- Contract values (`Files`, `Clock`) are Go interfaces; give concrete types a `var _ Files = (*osFiles)(nil)` assertion.
- `string` is UTF-8; `Int` is `int`; always-64-bit host values stay `int64` and convert with `FitInt` or `clampInt`. `List[T]` is `*List[T]` with `Items`; `Map` and `Set` keep insertion order and match keys with `*Keys[K]`.

## Representation and build inputs

Reference-versus-value rules are in [Go representation](go-lowering-representation.md): records and collections alias; `Option`, `Result`, alternatives, and contracts are values.

`msruntime.Sources` lists every non-test `.go` file except `bundle.go`. It feeds pin identity, the shared workspace, and `Standalone` bundles. Keep one import alias per path, because bundling folds files together.

## Host escalation

Cleanup waits for work to end. The runtime cannot terminate a goroutine, so work ignoring cancellation can block cleanup forever. Escalation is the host's last resort: it ends the process and never reports stuck work as joined.

Each host runs one watchdog, started when the host begins shutdown or gets a stop request (SIGINT, SIGTERM, server shutdown), not by ordinary timeouts. It covers `with` cleanup and resource close.

| Setting | Default |
| --- | --- |
| Grace period after the stop request | 30 seconds |
| A second stop request during the grace period | Escalates immediately |

On escalation the host:

1. writes one stderr diagnostic per outstanding operation with its current suspension location, and accepted stop reason;
2. writes retained primary and secondary fault diagnostics;
3. terminates without further cleanup.

The CLI exits 70, labeled incomplete cleanup. Native `RunMain` and the test runner implement the grace period and second-request rule but today write one `incomplete cleanup: <reason>` line, and the grace period is not configurable. Conformance treats an escalated exit as program failure. See [cleanup faults](../core-language/cleanup/cleanup-faults.md).

## Verifying

- `go build ./pkg/runtime && go vet ./pkg/runtime`
- `go build -tags rtcheck -gcflags=-e ./pkg/runtime` shows no `std_*_gen.go` errors.
- `go test ./pkg/runtime`.
- `make stdlib-test` and `make e2e` run fixtures end to end.
