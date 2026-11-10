# Arena: owned slots addressed by generation-checked handles

## Summary

- Problem: the one-owner model has no way to express cross-linked data (graphs, parent pointers, doubly linked lists, ASTs with back references); users reach for `Map[Int, T]`, which is slow, or cannot write the program.
- Change: `@std/collections/arena.ms`, an `Arena[T]` that owns values in one flat list and hands out copyable `Id[T]` handles. Pure `.ms`, no runtime primitive, no new syntax.
- Decision requested: ship the stdlib module as prototyped, and do not build a region/bump allocator in the runtime (see Alternatives).

## Status

Proposal with a working prototype; 2026-11-10; checked at `c6a7c5f3`. Not merged as a language change: nothing here changes syntax or the checker.

## Problem

A record has one owner and a field cannot view another variable (`references.md`), so a node cannot hold its parent or a sibling. The usual workaround costs a hash per link:

```manuscript
var m: Map[Int, Rec] = Map[Int, Rec]()   // links are Int keys
```

Measured in `bench/perf/arena/main.ms` (churn: add one record, remove the one added 1000 steps ago, 2M steps): `Map[Int, Rec]` 93 to 114 ms.

## Design

```manuscript
import Arena, Id from "@std/collections/arena.ms"

type Node:
    name: String
    next: Id[Node]?

var a = Arena[Node]()
first := a.add(Node(name: "a", next: none))      // moves the value in
second := a.add(Node(name: "b", next: first))    // Id is a scalar: copies freely
if n := a.get(second):                           // borrows; none once removed
    print(n.name)
a.update(first, fn(var n: Node) Unit: n.name = "z")
old := a.remove(first)                           // moves it out; old handles go stale
```

- `Arena[T]` owns `List[T?]` slots, a generation per slot and a free list. Dropping the arena drops every value in slot order through the normal drop glue.
- `Id[T]` is `enum Id[T]: At(raw: Int)`. An alternative that carries only primitives is `Copy`, so no new copy rule is needed; `T` is a phantom parameter and distinguishes `Id[Node]` from `Id[Edge]`. `raw = generation * 2^32 + slot` (no bit operators exist, so the packing uses `*`, `/`, `%`).
- Memory model: one owner (the arena); `add` and `remove` move; `get` returns a borrow of the slot (the arena cannot change while it is held); `.clone()` of the arena is the only copy, so `T` must be `Clonable` for it. Ids are not borrows, so they escape and outlive freely; a stale or foreign id reads as `none`, never as another value.
- In-place change goes through `update(id, change)`: the value is moved out of its slot, changed, and moved back. `if var v = a.get(id)` is rejected by the checker (`if var` accepts only `place[key]?` and `Map.get`), and `get` cannot return an exclusive borrow of a `T?` slot. Cost: two shallow moves per update.
- Faults: none. `get`, `remove` and `update` report a stale id as `none` or `false`; handle reuse needs 2^32 removals of one slot to wrap.

## Measured (prototype, same binary, `ms run`, 4-core Linux container, three runs)

| Benchmark | Boxed or Map | Arena | Ratio |
| --- | --- | --- | --- |
| churn 2M add/remove, window 1000 | `Map[Int, Rec]` 93 to 114 ms | 37 to 53 ms | 2.0x to 2.8x faster |
| binary tree depth 16, build and check, x20 | recursive `enum Tree` 29 to 32 ms | 80 to 91 ms | 2.7x slower |

The second row is the honest limit: the existing size-class allocator already makes a boxed node about 11 ns to allocate, check and free (`crates/ms-rt/src/alloc.rs`), so an arena does not speed up trees that the language can already express. The arena earns its place for shapes the owner model cannot express (links in both directions) and against `Map`, not as a faster `malloc`. The cost in the tree row is the checked `get` (bounds, generation, occupancy, optional-of-optional); an unchecked `at` is possible but would fault instead of returning `none`, which this proposal does not recommend.

## Runtime primitive

None. `List[T?]`, `List[Int]` and the existing allocator suffice. A bump allocator was considered as the primitive and rejected on the numbers above: boxed allocation plus free is already about 11 ns per node, so a region has little headroom left to win, and a region would need lifetimes or borrow rules that the model deliberately lacks (nothing allocated in it may escape its scope, and owned strings and lists inside would still malloc).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/collections/arena.ms` | new module (embedded by `ms-check/build.rs`) | `tests/e2e/testdata/stdlib/arena.ms` |
| `bench/perf/arena/` | churn and tree benchmark | `ms run bench/perf/arena/main.ms` |
| docs | `collections.md` entry and generated reference, not yet written | `make docs` |

## Alternatives considered

- Do nothing: keep `Map[Int, T]` for links. Works, 2x to 3x slower on churn, no stale-handle protection.
- Region allocator primitive (`msrt_region_*`): rejected above on the numbers and on escape rules.
- Plain `Int` ids over a `List[T]`: fastest, no generation, so a reused slot silently aliases a removed value. Callers can still do this with `List` today.
- Built-in `Arena[T]` type in the checker (the plan in `crates/DESIGN.md`): unnecessary; the stdlib type needs no checker support. If it is later built in, `Id[T]` can keep this layout.

## Open questions

- In-place access without moves: a checker rule letting `if var v = a.get(id)` borrow a `List[T?]` slot would remove the `update` callback. Separate language change, needs Chinmay's ok.
- Whether `Id[T]` should hash and compare (`Hashable`, `Equal`) for use as map keys: an enum of one Int should derive both; not verified.
- Unchecked fast read for hot loops, if checked `get` proves too slow in real programs.
