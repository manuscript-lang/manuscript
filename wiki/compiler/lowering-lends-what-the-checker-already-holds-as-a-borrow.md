[Wiki](../index.md) › [Compiler and build](index.md)

# Lowering lends what the checker already holds as a borrow

Decision: a container read the ownership checker holds as a lexical borrow (`let x = m.get(k)`, `if let x = xs.first()`, `m.get(k).get()`, `m.get_or(k, d)`) must not copy the entry. Lowering reads the entry in place (`msrt_map_get_ptr`, `list.get.u`) and builds `opt.view`, an optional that borrows its payload and is never dropped (`crates/ms-lower/src/lend.rs`).

The same holds for source lenders: a callable in `Program.lenders` lowers with `Func.ret_borrowed`, so `Module::result_mode` classifies its call results as borrows (the verifier, `lastuse`, `copyelim` and `inline` all read that one function), `emit_return` returns the reference without `owned()`, a `let` of the call is bound lent, and a lend from a temporary (`Program.owned_lends`) is copied at the call before the temporary is dropped. The verifier rejects an owned value returned from a lender, so a lowering path that still copies shows up as `ret: %v is owned, but this function lends its result`.

Interface views are the owned cousin: a callable in `Program.view_lenders` lowers with `Func.ret_view`, `fit_ty` of a borrowed value emits `iface.lend` (a box of the leaves as they are, vtable tag 1, dropped like any owned value but freeing only the box), and a view local returned at its last use is taken out with its scope drop skipped on that path (`view_moves`, `closed_on_path`). `Module::result_views` tells `lastuse` and `copyelim` that such a result points into the operands; the copy of a value that may be a view is never elided into a move, since the copy is what makes the stored value own its payload.

Apply when: adding a lowering path for an accessor result, a payload binding or a join of two borrows (`two_ways_mode`), a MIR op that produces a borrow, or a new way a call result is bound.
Evidence: [lent reads](../../crates/ms-lower/src/lend.rs), [fixture](../../tests/e2e/testdata/accept/borrowed-container-reads.ms), [lastuse and simplify tests](../../crates/ms-mir/tests/opt_lastuse.rs), [proposal](../../proposals/borrowed-results.md).
Verify: `ms emit` of the fixture shows `msrt_map_get_ptr` and `opt.view`, no `msrt_map_get`; `make stdlib-bench BENCHFILTER=map.get` keeps `map.get_let` within 1.2x of `map.get_chain`.
