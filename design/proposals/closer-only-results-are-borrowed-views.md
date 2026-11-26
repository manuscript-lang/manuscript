# A `&` result of a resource with only a `close` is a borrowed view

## Summary

- Problem: a resource whose type has `fn move close()` but no drop glue (a "closer-only" type: `Promise`, a file handle, a user `Marker`) is treated as an owned alias of its receiver wherever a call answers it as `&T`. Its owner and the alias both close it, or a temporary the call read is never closed (#7217).
- Change: lowering treats a `&T` result of a closer-only `T` as borrowed, exactly as it already does for a type with drop glue, and closes the temporaries such a call read.
- Decision requested: none; this makes lowering follow the existing `&` and `hold` rules. One user-visible effect: a method value that would hand out a non-clonable resource twice is now a checker error.

## Status

Proposal, 2026-11-26, checked against `main` at `fbfa11dcb0`.

## Problem

The borrowed-view machinery assumes only a drop type is borrowed: `borrows_result` (`lower_func.c`) and `mir_result_mode` (`mir_analysis.c`) both gate on `mir_needs_drop`. For a closer-only type that gate is false, so the instance is not `ret_borrowed` and the caller owns what it was handed.

```ms
type Marker { id Int }
fn move Marker.close() Void! { print(f"closed-{self.id}") }
fn run() Void {
	var items = [Marker(1)]
	spare := Marker(2)
	found := items.get_or(0, spare)   // `&Marker`: a view of items[0]
	print(f"found-{found.id}")
}
```

`found` and `items` both close `Marker(1)` (`get_or` also ICEs while lowering with a resource `T`). Further cases, each a row of `make resource-matrix`:

- `void client.fetch(..).with(..).wait()` (`tests/lang/stdlib/http2-cancelled-requests.ms`): the stream of `fetch` is never closed once `with` is borrowed.
- `success(id).get().id` (`tests/lang/try-result/result-get-scalar-resource.ms`): the `Result` temporary must still close.
- `f := items.remove; f(0)`, `items.set`, `map.add` as method values leak the entry they drop.
- `f := items.get_or; f(0, v)` and `held.get_or` (a `move` receiver) double close.

## Design

One rule: a call whose declared result is `&`/`hold` borrows from its argument whether or not the result type has drop glue.

- `borrows_result` marks the instance `ret_borrowed` when the result is a resource (`ms_check_holds_resource`) even if `mir_needs_drop` is false.
- `fn_is_borrowed_view` asks `mir_result_borrowed` of the call, with no drop gate, so a bind of such a result views it.
- A bind whose call reads an owner at its last use (`items.get_or(..)` as the last use of `items`) borrows when the result is not a part of a temporary built in the call: the owner still closes at its scope end (`borrows_call_temporary`). A part of a built temporary stays on the take-or-clone path.
- `ms_own_moves_instance` takes the declaration node so returning a plain parameter whole from a `&` function is a view, not a move (fixes the `get_or` ICE).
- `callee_consumes` (`lower_temp.c`) does not count `return self` of a `&` result as a consume: the caller still owns the argument and closes the temporary.
- `temp_type` keeps skipping a temporary whose result may be kept past the statement (`fn->temps_keep`: a bind other than `_`, or a return, whose type holds a resource). A statement that discards the value, or yields a scalar, closes the temporary at its end. `fn_stmt_keeps_resource` computes the flag once per statement.
- `bound_native_method` initializes the closing tables of the closure body (`fn_init_closing`) so the natives that drop what they take out (`remove`, `set`, `add`, `splice`, `clear`) close it, as a direct call does.
- Checker, `stmt_bind` (`bodies.c`): `f := value.method` is an error when the method consumes a resource receiver or answers a `&` resource that is not clonable. The value can be called twice and has no second owner to give. The accepted fixture that encoded the unsound case moves to `tests/diagnostics/types/ms3000-a-method-value-cannot-hand-out-a-resource-twice.ms`.

```ms
fn run() Void {
	held := Marker(1)
	f := held.finish   // MS3000: a method that consumes a resource or answers a view of it cannot be used as a value, since the value could be called twice; call the method directly
	r := f(false)
}
```

Edge cases: a clonable `&` result (`&String`) still clones inside the closure, so `source-capture-borrowed-string-result` is unchanged. Closer-only types with a `.clone()` are unaffected by the checker rule.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/lower/lower_func.c`, `lower_scope.c`, `lower_stmt.c` | borrowed-view rule, last-use bind | `tests/lang/ownership/closer-only-view-results-close-once.ms`, `make resource-matrix` |
| `src/compiler/lower/lower_temp.c`, `lower_fn.h` | `callee_consumes`, `temps_keep` | `http2-cancelled-requests`, `result-get-scalar-resource`, `promise-semantics` |
| `src/compiler/lower/lower_closure.c` | closing tables in a bound native body | same fixture (`remove`, `set`) |
| `src/compiler/own/moves.c` | `ref_result` for instances | same fixture (`get_or`) |
| `src/compiler/check/bodies.c` | method value rejection | diagnostics fixture above |

## Measured benefit

- `make resource-matrix`: every operation, call form and argument form closes each resource once (11 failing rows before, none after).
- Performance: the MIR of 84 of the 85 programs under `bench/perf/` is byte-identical before and after. The one that differs is `compile_time_incremental.ms`, a setup tool: it now closes a `TemporaryDirectory` it used to leak. No speed claim changes.

## Alternatives

- Do nothing: leaves #7217 and keeps the matrix out of the nightly; the leaks and double closes are silent.
- Patch each operation (`get_or`, `remove`, ...): a name-keyed special case per row, which the repository rules forbid; the cause is the one drop gate.
- Make closures return owned copies of a closer-only result: a resource has no copy, so the value would alias its owner.
- Give function types a borrowed-result flag so `call.ind` results are views: a language-level type change for a corner the checker rule already makes unreachable. Left as future work if method values over resources are wanted.
