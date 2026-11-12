[Wiki](../index.md) › [language](index.md)

# Interface conversion rules

Implicit interface conversion, no construction syntax, borrowed values becoming views. Each section is one lesson.

## Implementing types convert to their interface implicitly

Decision (Chinmay, reversing the explicit-view rule): a type whose own methods satisfy `I` passes wherever `I` is expected (originally a declared `impl I for T`). The conversion follows the position: a read-only argument borrows the operand, a stored position moves it at its last use; the interface value owns a copy when the operand is borrowed.

## Interfaces convert implicitly; construction is removed

Status: in flight (PR #1135, not yet on main as of this note). Decision: a value converts to an interface at a typed binding or argument (`v: Shape := x`), and `Shape(value: x)` / `Shape(x)` fail with "cannot be constructed"; about 260 stdlib and fixture uses were migrated. Re-check the checker before relying on either spelling.


Apply when: touching interface views, generic matching, or conversion diagnostics.

## Interface conversions of borrowed values are views

Decision (Chinmay, 2026-11-01, "tagging makes sense, let's do it, save on clones"): converting a borrowed value to an interface (`return cause` as `Reportable`, `e: Reportable = cause`, a widened borrow-returning call, `?` of one) builds a view, never a copy. The vtable word's low two bits say what the interface value owns (0 box and payload, 1 box only, 2 nothing); a function returning one is a *borrow-returning view function* (`ResultBorrow.view`, `Func.ret_view`) whose result the caller owns and drops while holding the arguments. Stage 2 of [proposals/views.md](../../proposals/views.md), PR #2211.

Verified (leak-check, 2026-11-01): an interface with a `var fn` operation (`ReadStream`, `WriteStream`) must keep copying a borrowed operand (`contract_mutates`, checked in both `view_source` and `fit_ty`). Natives such as `copy` call `var fn` operations on the box without the checker's `var` discipline, so a write into a box of borrowed leaves frees the owner's value and leaks the new one (`io-generic-streams.ms` writing into a `Mem` sink). A checked `var` call already requires `var x: Sink`, so Manuscript code never reaches this; do not widen views to mutating interfaces until natives take `var`.

Verified (adversarial review, 41 programs under valgrind): a view local handed on without the checker noticing is the hole to test for. `e := first_error(cause); return relay(e)`, `return id(first_error(cause))` and `e2 := e; return e2` each dangled or ICEd until `view_moves` covered relays of a view local and `e2 := e` at `e`'s last use handed the box on; with `e` used later, `e2` is a plain reference into `e`'s box (origin `e`, not `cause`), so returning or relaying it is rejected. The checker and lowering must agree on what is a view: when the checker calls a conversion a view but lowering copies, the result is still owned and sound; the reverse (lowering lends, checker thinks copy) is a use-after-free.

Verified (bug bash, 2026-11-01): an interface value has no `.clone()` (an interface such as `Reportable` offers only its declared operations), so a remedy that says `e.clone()` is a dead end and its machine fix breaks the build. Ownership diagnostics for interface and function values (`no_clone` in `walk.rs`) say to use the value in place or convert a clone of the concrete value. Probed ~60 adversarial programs under valgrind (Debug and Release) over wrapped lends, view locals, conditionals, closures, tasks and resources; the checker held.

Apply when: changing interface conversion, `fit_ty`, borrow-returning view function, the vtable layout, `copyelim`/`lastuse` on owned results, or adding `var fn` to a stdlib interface (its conversions start copying again; say so in the PR).
Evidence: [OWNERSHIP.md](../../crates/ms-check/OWNERSHIP.md), [DESIGN.md](../../crates/DESIGN.md), [interface_views](../../crates/ms-check/tests/ownership/accept/interface_views.ms), [interface_view_held](../../crates/ms-check/tests/ownership/reject/interface_view_held.ms), [e2e interface-views](../../tests/conformance/fixtures/e2e/accept/interface-views.ms).
Verify: `fn first_error(cause: Cause) Reportable: return cause` compiles with no copy and `first_error(c).message()` after `c.code = 5` sees 5; `e: Reportable = cause; return [e]` is rejected with a `.clone()` remedy; `make leak-check` passes with `io-generic-streams.ms` swept.

## A type's own methods satisfy an interface by shape

Decision (Chinmay, 2026-11-10 and 2026-11-11): a type has one method per name, so a `Source` plus `Sink` with two `close` bodies is the wrong shape. Methods are receiver functions (`fn Type.name`, `fn var Type.name`; generics repeat the parameters, `fn Box[T].get()`; a receiver may carry bounds, `fn Box[T: Equal].same()`, or fix an argument, `fn List[Int].sum()`), and an interface is satisfied when the own methods match every operation. There is no `impl` keyword; nothing declares conformance.

What carries it: `shape_implements` in `contracts.rs` (records, enums, natives and primitives; it picks the own method whose signature the operation asks for, and matches operation type parameters by position); lowering falls back to the own method by name where a contract impl was once required (`contract_impl`, `user_order`, `json_encode_impl`, `fixture_hook`); `Method::closes` makes an own `fn var close() Unit!` `Closeable`, and `Method::overrides` makes an own `equals`, `hash`, `compare` or `to_json` the type's `Equal`, `Hashable`, `Comparable` or `JsonEncode`. `Clonable` and `Data` are derived; a bundled native type states them with a `// ms: data|clonable` comment above it. `Decimal` is the one native classified as plain words (`Class::Copy`), by identity like the primitives; there is no `Copy` interface. Generated interfaces (`Name$methods`, one per bounded or specialized receiver form) carry the receiver methods' signatures without defaults; defaults stay on the method.

Lessons:
- Any own `fn var close() Unit!` makes a type `Closeable`, so a scope end calls it. A stream driver that a `ReadStream`/`WriteStream` also closes needs an idempotent `close` (a `closed` flag, or an id set to a dead value), and a helper that only borrows the driver's behaviour must not build a driver value (`Pipe.receive` called `PipeSource.next` on a local, which closed the reader at scope end; it calls `pipe_next` now).
- Contract defaults are not inherited: restate a default on the own method (`options: RunOptions = RunOptions()`); an interface view uses the interface's.
- One method per name also removed: two applications of one generic interface on one type (`Visitor[Int]` and `Visitor[String]`), a field and a method of one name, and per-module extensions with their module-scoped `Equal`/`Hashable` (the `core_parity`, `map_add_scope`, `map_remove`, `preferred_names`, `set_operand_hash`, `interface_views` and `local_extensions` e2e projects were deleted with them).
- `make e2e` runs `target/debug/ms`; rebuild it (`cargo build -p ms-cli`) before trusting a result, or a stale binary reports failures that are gone.

Evidence: `tests/conformance/fixtures/e2e/stdlib/shape-interfaces.ms`, `stream-close-once.ms`, `reject/shape-interface-mismatch.ms`, `reject/duplicate-receiver-method.ms`, [proposals/receiver-methods.md](../../proposals/receiver-methods.md).
