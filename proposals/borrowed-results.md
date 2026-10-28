# Borrowed results: lend container reads instead of copying them

## Summary

- The checker already treats the result of a lending accessor (`m.get(k)`, `xs.first()`, `xs.last()`, `m.get_or(k, d)`) and of a user function declared `-> ref T` as a lexical borrow of its origin. Lowering ignores most of that and deep-copies the value out of the container.
- Change: lower a `let` binding or an `if let` scrutinee of a lending accessor to a pointer into the container (`msrt_map_get_ptr`, `list.get`) and a new borrowed optional, so no copy, no allocation and no drop. Stage 2 gives `ref` functions a borrowed result mode in MIR so their callers receive a borrow too.
- Cost: one MIR op (`opt.view`), `Func.ret_borrowed` on MIR functions (stage 2, #1292), lowering changes in `crates/ms-lower`, no language or standard-library change.
- Decision requested: none on the language. The owner asked for this ("we're not applying ref properly, that would cause a copy from containers", 2026-10-25).

## Status

Stage 1 implemented, 2026-10-25, on `0d405aac`. Direction quoted above; the checker rules it relies on are in `crates/ms-check/OWNERSHIP.md` ("Borrows are lexical", "Borrowed results"). Skeptical review (2026-10-25): build with changes. Applied: `simplify` aliases only `opt.get` of `opt.view` (`opt.unwrap` owns its result); the verifier rejects `opt.view` of a boxed optional; a `lastuse` test pins that `drop map` stays after the lent load; `two_ways_mode` joins borrows.

Stage 2 for the standard library landed independently in #1292 (same day): `Func.ret_borrowed` marks a lending function, `opt.view` is the borrowed optional (the stage 1 branch had introduced the same op as `opt.lend`; the two were folded into `opt.view` when the branches met), `return some(part)` and returned `match` payloads lend, and `JsonValue.get/at/as_*` borrow. Remaining: user-declared `ref` functions still copy at return, because an interface-call result is owned; the open question is who copies when a lending implementation is reached through a vtable (the method thunk, or a second body). A lambda cannot return a borrow of its parameter, so `opt.and_then(lambda a: a.get(k))` over a lending `get` is rejected; read levels with `if let`.

## Problem

Verified (`ms emit` on the probe below at `0d405aac`):

- `let found = orders.get(id)` lowers to `call.rt @msrt_map_get`, which copies the whole `Order` (two strings, a list, each item's string) into an `Optional` slot, then drops it at scope exit. `orders.get(id).get()` in one expression lowers to `msrt_map_get_ptr` plus a `load` and copies nothing (`crates/ms-lower/src/mapset.rs`, `map_get_chain`).
- `if let o = orders.get(id):` copies the `Optional`, binds `o` as a borrow of it, and drops the copy at the end of the branch.
- `if let s = opt:` with a record payload copies the payload: `bind_local` lends only strings (`crates/ms-lower/src/func.rs`), while `let` lends any `opt.get`/`list.get`/`rec.get` result (`crates/ms-lower/src/stmt.rs`, `bind`).
- `let o = m.get(k).get()` lends only when `m` is a read-only parameter (`stable_place`); on a local `var m` it copies, although the checker rejects changing `m` while `o` lives.
- `m.get_or(k, d)` copies the entry into an `Optional`, copies the payload out of it, then drops the `Optional`: two copies for one read.
- `xs.first()` and `xs.last()` call `msrt_list_first`/`last`, which copy the element into an `Optional` slot.
- `def name() -> ref String: return self.name` copies at `return` (`emit_return` always owns); the caller receives and later drops an allocation per call. MIR `Func.ret` has no result mode ("results are always owned", `crates/ms-mir/src/ir.rs`).

Measured (callgrind, `scratchpad/probes/mapget`, 300K lookups per shape of an `Order` with two items): the `let found` and `if let` shapes spend 2 allocations and 2 frees per hit on the copy and run about 3x the instructions of the chain shape. Agent-written programs use the copying shapes (`bench/agent/challenges/c13-inventory-orders/solutions/ms/main.ms.ref`: `let have = w.stock.get(it.sku)`).

- Found while checking the example: `return o.items.get(0).sku` from a `ref` function is rejected (`get` borrows its result from `o.items`; use it in place), while `return o.items[0].sku` is accepted. The checker's lending-call chain stops at a field read of a borrowed call result; tracked as a round-3 finding, outside this proposal.

Non-goals: `Shared[T]` (separate redesign), changing what the checker accepts, string views (`proposals/string-ownership.md`).

## Design

Rule: a value the checker holds as a lexical borrow is lowered as a borrow, never copied, wherever the lowering can name its origin.

Programs do not change. Before and after is the same source with fewer runtime calls:

```manuscript
fn stock_of(w: Warehouse, sku: String) Int:
    let have = w.stock.get(sku)     # a pointer into the map, not a copy of the entry
    if have.is_none():
        return 0
    return have.get()

fn first_sku(o: Order) ref String:
    return o.items[0].sku           # returned as a borrow of o (stage 2)
```

- **Borrowed optional (MIR).** New op `opt.view %payload -> opt<T>`: wraps a borrowed payload into an `Optional` that is itself a borrow. Operand mode `Borrow`, result mode `Borrow` (`arg_modes`, `Module::result_mode` in `crates/ms-mir`). Codegen is identical to `opt.some`. The verifier's linear ownership is unchanged: a borrowed optional is never dropped and never passed to a consuming position. `simplify` folds `opt.is_some` and `opt.get` over it as over `opt.some`.
- **Boxed optionals.** `Optional[T]` where `T` contains `Optional[T]` by value is a heap box (`ms-clif/src/layout.rs`, `opt_is_boxed`); `opt.view` on such a type would allocate without an owner. Lowering keeps the copying path for those. The boxing test moves to `ms_mir::Module` so lowering and layout share one definition.
- **`let x = accessor` (immutable name, function vetted by the ownership checker, binding not captured by a closure slot).** Lowering recognizes `Map.get(k)` (exact key type), `List.first()`, `List.last()` and emits the entry pointer or index, a presence test, and `opt.view` of the loaded payload joined with `opt.none` through a borrow-mode block parameter. The binding is `bind_lent`; temporaries the pointer depends on live as long as the binding (existing `bind_hidden` rule).
- **`if let x = accessor` (same conditions).** No `Optional` at all: the test is the presence test and `x` is the loaded payload, lent. This is the `let` path of `alias_accessor` (`crates/ms-lower/src/alias.rs`) without the write-through alias.
- **`if let x = opt` payloads.** Lend the payload under the same rule `let` uses (`opt.get`/`alt.get` of a scrutinee that is itself not owned); an owned scrutinee (`if let x = parse(s)`) still copies, because the scrutinee is dropped at the end of the branch.
- **Chain reads.** `let o = m.get(k).get()` lends whenever the function is vetted, not only for read-only parameters: the checker rejects changing or reassigning `m` while `o` lives.
- **`m.get_or(k, d)`.** Lower through `msrt_map_get_ptr`: one copy of the payload on a hit, the fallback otherwise. Bound by `let`, both arms are borrows and the binding is lent when `d` is a place.
- **Stage 2: `ref` function results.** `Func.ret` gains a `Mode`; a `ref` function with `Summary.result` non-empty returns a borrow (`ret` accepts a borrowed value when the function's result mode is `Borrow`), and `Call` results take the callee's mode. `emit_return` stops copying in such functions; a borrowed result that a caller stores or consumes is already rejected by the checker, so callers copy only where the lowering must own (`owned()` on a `Val { own: false }`, as today). Interface calls and closures stay owned.
- **Ownership and safety.** Every lent value corresponds to a borrow the checker already enforces (OWNERSHIP.md "Borrows are lexical", "Borrowed results"). Standard-library source that the checker has not vetted (`ownership::is_vetted`) keeps copying.
- **Errors, cancellation.** Unchanged: no new runtime entry points; faults for `get()` on `none` stay where they are.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir` (`ir.rs`, `verify.rs`, `builder.rs`, `interp.rs`, `opt/simplify.rs`, `opt/optparam.rs`) | `Op::OptView`; `Module::opt_is_boxed`; stage 2: `Func.ret_mode` | `opt_simplify` unit test for `opt.view`; verifier test that `opt.view` of a borrow is accepted and a drop of it rejected |
| `crates/ms-clif` (`lower.rs`, `layout.rs`) | `OptView` codegen shares `OptSome`; layout uses the module boxing test | existing e2e |
| `crates/ms-lower` (`stmt.rs`, `mapset.rs`, `alias.rs`, `func.rs`) | lent lowering of `let`/`if let` accessor reads, `if let` payloads, chain reads, `get_or`; stage 2 `emit_return` | new `tests/e2e/testdata/accept/borrowed-results.ms`; MIR shape test: no `msrt_map_get` in the probe |
| `crates/ms-check` | unchanged (rules already exist) | existing conformance `ownership` fixtures |
| `stdlib/*.ms`, `bindings.json`, `ms-rt` | unchanged | |
| `bench/perf/stdlib` | cases `map.get_let`, `map.get_if_let`, `map.get_chain`, `map.get_or` as the gate: `let` and `if let` within 1.2x of the chain shape (measured 26, 24, 29, 28 ns/op) | `make stdlib-bench BENCHFILTER=map.get` |
| Docs | `crates/DESIGN.md` MIR section notes `opt.view` and the result mode | `make repo-check` |

## Alternatives

- **Do nothing.** Agent programs keep paying a deep copy per lookup, and `-> ref T` on a user function has no runtime effect, which contradicts the documented contract.
- **Teach programmers the chain shape.** `m.get(k).get()` already lends, but the owner wants the natural shape fast; the checker already proves the natural shape safe.
- **Pointer-shaped locals (no MIR op).** Represent a lent optional local as a nullable pointer and rewrite each use. Rejected: every use site of the local (`is_some`, `get`, `if let`, `match`, passing to a function) needs its own rewrite; `opt.view` reuses all existing `Optional` lowering.
- **Make `opt.some` accept a borrowed operand.** Rejected: its result mode is `Own` by op, and `optparam`/`lastuse` reason about moves into `opt.some`.
- **Checker changes.** None needed; the lowering catches up with rules already enforced.

Drawback: lowering has two paths for one source shape (vetted lends, unvetted copies); that split exists today for strings and list elements.

## Staging and verification

1. Stage 1: `opt.view`, lent `let`/`if let` accessor reads, lent `if let` payloads, chain reads, `get_or`. Gate: `make verify`, `make conform`, e2e fixture, probe within 1.2x of the chain shape, workloads `bench/perf/workloads/run.sh` not slower.
2. Stage 2: MIR result mode and `ref` function results. Gate: same, plus a fixture where a `ref` getter is called in a loop and callgrind shows no `msrt_str_dup`/copy per call.

## Open questions

None for the language or user-visible behavior. Stage 2 needs the interface-dispatch answer recorded in Status before it is built.
