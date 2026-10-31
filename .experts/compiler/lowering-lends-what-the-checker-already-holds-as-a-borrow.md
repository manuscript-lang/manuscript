[Wiki](../index.md) › [Compiler and build](index.md)

# Lowering lends what the checker already holds as a borrow

Decision: a container read the ownership checker holds as a lexical borrow (`let x = m.get(k)`, `if let x = xs.first()`, `m.get(k).get()`, `m.get_or(k, d)`) must not copy the entry. Lowering reads the entry in place (`msrt_map_get_ptr`, `list.get.u`) and builds `opt.view`, an optional that borrows its payload and is never dropped (`crates/ms-lower/src/lend.rs`).

Verified: before this, `let found = orders.get(id)` deep-copied the record (two allocations and frees per hit) while the same read written as one chain lent; `if let` copied the payload for every type but `String`. Lending is gated on `ownership::is_vetted`, an immutable name no closure slot shares, and a payload whose optional is not boxed (a recursive `Node?` has no owner for the box; the verifier rejects `opt.view` of it). `lastuse` keeps `drop map` after the lent load because the pointer and everything loaded through it join the map's family.

Apply when: adding a lowering path for an accessor result, a payload binding or a join of two borrows (`two_ways_mode`), or a MIR op that produces a borrow.
Evidence: [lent reads](../../crates/ms-lower/src/lend.rs), [fixture](../../tests/e2e/testdata/accept/borrowed-container-reads.ms), [lastuse and simplify tests](../../crates/ms-mir/tests/opt_lastuse.rs), [proposal](../../proposals/borrowed-results.md).
Verify: `ms emit` of the fixture shows `msrt_map_get_ptr` and `opt.view`, no `msrt_map_get`; `make stdlib-bench BENCHFILTER=map.get` keeps `map.get_let` within 1.2x of `map.get_chain`.

---
Topics: [Ownership and value semantics](../topics/ownership-and-values.md)
