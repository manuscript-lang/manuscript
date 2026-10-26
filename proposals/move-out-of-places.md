# Move out of places: `replace` and `swap`

## Summary

- Problem: Manuscript cannot move a value out of a list slot, field or `var` borrow, or exchange two slots, without cloning. `Queue.dequeue`, `Queue` compaction and every `PriorityQueue` sift step clone for this reason.
- Change: two small primitives and no new syntax.
  - `replace(var place, value) -> T` moves `value` into the place and returns the old value.
  - `swap(var a, var b)` exchanges two disjoint places, and `List.swap(i, j)` does the same for two indexes of one list.
- Both keep the place initialized at every point, so the checker needs no hole or partial-move tracking.
- Status: **proposed**. Decision requested: approve the primitives, or choose another option below. Nothing is implemented.

## Problem (verified in source)

The model has "moving out of a borrow is rejected" and "`x` cannot be reassigned or moved out" for `var x = a[i]` (`crates/ms-check/OWNERSHIP.md`, Borrows and Mutable borrows). `set(i, v)` consumes `v` and drops the old element. So the only way to take an element and keep the list valid is `.clone()`, then overwrite.

| Site | Clone it pays |
| --- | --- |
| `stdlib/queue.ms` `Queue.dequeue` | `items.get(head).clone()` then `set(head, none)` |
| `Queue.enqueue` compaction | `live.append(items.get(index).clone())` per live item |
| `PriorityQueue.enqueue` | `entry.clone()` for the append, then `shift` clones one entry per level |
| `PriorityQueue.dequeue` | `top` clone, `last` clone, then `shift` clone per level |
| `List.copy_within` | clones, **but by necessity**: it duplicates a range, as Rust's `copy_within` does only for `Copy` types. It is not this problem; a move-based `rotate` or `move_within` would be a separate request |

Cost is not measured yet. For `PriorityQueue[String]` each sift level allocates and frees one `String`; for scalar payloads the clone is a memcpy. A benchmark (`bench/perf`) should be run before and after stage 1 and the result page extended, per `AGENTS.md`.

## Design

```manuscript
# Prelude, from @std/core.ms
def replace[T](var place: T, value: T) -> T: ...
def swap[T](var a: T, var b: T) -> Unit: ...

impl List[T]:
    var def swap(i: Int, j: Int) -> Unit: ...
```

- `replace(var xs[i], none)` takes an `Optional` slot. `replace(var self.head, next)` moves a field. Both accept any place a `var` argument accepts today (`shift(var pts[i], dx)` is already in `lowering-element-places.ms`).
- Checker: a call is an exclusive borrow of each `var` place for the call and the existing overlap rule applies (`f(var a, a)` is rejected). So `swap(var self.a, var self.b)` checks (disjoint fields) and `swap(var xs[i], var xs[j])` is rejected exactly like `f(var xs, xs)`: indexes cannot be proven disjoint statically. `List.swap(i, j)` covers that case, as `slice::swap` does in Rust, with a bounds fault on invalid indexes.
- The result of `replace` is an owned value; `swap` and `List.swap` return `Unit`. No new ownership class, no change to `exclusive`, `lenders` or `read_borrows`.
- Lowering: a `var` parameter of a `Move`-class type is already passed as the address of the place. `replace` is a load of the old value into the result and a store of the new one; `swap` is two loads and two stores. Both can be MIR ops or small generic natives that only need the value size. Nothing needs a type descriptor, because no drop runs and no value is copied.
- Declared in Manuscript source (`stdlib/core.ms`, `stdlib/collections.ms`). Library sugar stays in Manuscript: `def take[T](var slot: Optional[T]) -> Optional[T]: return replace(slot, none)`.

Queue with the primitives (no clones):

```manuscript
var def dequeue() -> Optional[T]:
    if self.head >= self.items.length():
        return none

    let value = replace(var self.items[self.head], none)
    self.head += 1
    return value
```

Binary heap: `dequeue` does `self.heap.swap(0, last)`, `pop()`, then sifts with `swap`. A swap-based sift moves three words per level where the hole technique moves one; both are memcpy and neither allocates, so the hole technique is not worth new language surface.

## Alternatives

| Option | Verdict |
| --- | --- |
| Do nothing; ship only the `List.swap` stopgap | Fixes `PriorityQueue` but not `Queue.dequeue`, compaction, `Optional` fields, linked structures or any user code. Every container would grow its own `take_at`-style native. Cheapest, least general. |
| Only `List.swap` and `List.replace` natives | Smaller checker risk, but Rust-side special casing per container and no field or `Optional` support. Violates "prefer a general primitive". |
| **`replace` / `swap` on `var` places (recommended)** | Covers lists, maps (`if var v = m.get(k)`), fields and locals with one rule. Plus `List.swap` for same-container indexes. |
| Move out with a hole (`let x = move xs[i]`) | Needs definite-initialization tracking per element. A dynamic index cannot be tracked statically, so the hole must live at runtime (an `Optional` slot and drop flag), which is what `Optional` + `replace` already is. Rejected. |
| Element handles (`var ref`, or `pair(i, j) -> (var T, var T)` like `split_at_mut`) | Needs `ref` in tuples or bindings, which `one-borrow-model.md` deliberately removed (`ref` only on results). Two exclusive borrows of one list violate the one-writer rule. Rejected. |
| `take` with a `Default` bound | Requires a default value for every `T` and an extra construct; `replace` subsumes it. Rejected. |

## Risks

- A `var` argument that is a borrowed payload or an escaping capture must stay rejected; the existing rules for `var` arguments already do this, and fixtures should pin it (`replace(var x, v)` for a `let` borrow).
- `replace(var xs[i], xs[j].clone())` is legal; `replace(var xs[i], xs.get(j))` is rejected by overlap. Diagnostics should suggest `List.swap`.
- Generic natives over `T` (`replace[T]`) must be correct for `Resource` types: `replace` moves a resource out and leaves another in, so nothing is dropped or duplicated. `swap` likewise.

## Staging

1. `List.swap` (already underway in the PriorityQueue thread) and `replace` / `swap` with checker fixtures, lowering, e2e, docs in `references.md`, and generated reference pages.
2. Convert `Queue` and `PriorityQueue` to the primitives; remove `shift` and the clones; rerun `bench/perf` and add a dated section.
3. Audit other stdlib clone-then-overwrite patterns (`deque.ms`, `sorted.ms`) and convert them.

## Review note

The AGENTS.md skeptical-reviewer pass has not run; this is the author's draft. The evidence above is from reading source, not from running the checker: the claim that the checker accepts `replace(var xs[i], v)` rests on `shift(var pts[i], dx)` and the overlap rule, and stage 1 must verify it first.
