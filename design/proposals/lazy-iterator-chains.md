# Lazy iterator chains: `split`, `lines`, `fields_by`, `map` and `filter` yield one item at a time

* Status: **Proposed** (2026-11-25, against `main` at `f29c5c29`)
* Authors: [Claude](https://claude.ai/code)
* Implementation: not yet implemented
* Supersedes / Extracted from: the `for`-over-`split` lowering (`source_split` in `lower_for.c`, #7105) and the list-fusion pass ([fuse-list-loops](fuse-list-loops.md)), for the shapes this covers; builds on stage 2 of [borrowed-fields-and-looks](borrowed-fields-and-looks.md) (a look record with a `next` that returns `&T?`)
* Direction: Chinmay, 2026-11-25: "lets do lazy iterations in ms as well, thats more efficient, and users can build a list if they want to"; the coordinator's brief: "like Rust's: each step yields a borrowed view of the source, no intermediate list"

## Summary

- Problem: `split`, `lines`, `fields_by`, `List.map` and `List.filter` build a list per call. `report`, `grep`, `pargroup` and `wordfreq` sit 1.3 to 1.9x Rust mostly on those lists. Two compiler special cases (a split loop keyed on the method name, a MIR list fusion for scalars) hide the cost for a few shapes only.
- Change: those methods return lazy iterators written in `.ms`. Each `next` yields a borrowed piece of the source; `.collect()` builds a list when the caller wants one.
- Decision requested: the API break (a call that used the list now ends in `.collect()` or is walked by `for`), already directed above.

## Motivation

- `wordfreq`: `data.lower().fields_by(...)` builds 112 MB of piece headers before the loop reads them once (#7121 rewrote the benchmark around it). `bench/perf/results.md` lists the other gaps.
- The loop special case covers only `for x in text.split(sep)` written literally; `lines()`, `fields_by`, a chain, or a split passed on still build the list (wiki `a-split-loop-walks-the-text-and-makes-no-list`).
- The fusion pass covers scalar elements and lambda-shaped callbacks only; strings and records still pay one list per stage (wiki `a-list-built-and-read-once-never-exists`).
- Verified 2026-11-25: a generic adapter over an interface-bound iterator (`type Mapped[I Iterator[T], T, U]`) does not compile today: the lowering passes a `var` receiver by value (`ICE: call: argument 0 has type Count but ptr is expected`), and a look wrapped in a generic record cannot be returned (`a & result must be a part of a hold argument`). Both are general bugs, fixed in stage 1.

## Proposed solution

```manuscript
fn longest(text String) Int {
    return text.lines().map(line => line.trim().length()).fold(0, fn n, len: n.max(len))
}

fn first_field(line String) String {
    return line.split(",").collect()[0].clone()
}
```

`lines()` and `map` allocate nothing; a piece is a view of `text`. `collect()` is the one place a list appears. Same shape as Rust's `iter().map().sum()`, with the one-owner rules: the iterator borrows its source, which cannot change or move while the iterator lives.

## Detailed design

**Iterator protocol (unchanged).** `Iterator[T]` is `var fn next() T?`. A look record with `&` fields and `fn var next() &T?` is an iterator whose items borrow the source, not the iterator, so `next` runs while earlier items are live (borrowed-fields-and-looks stage 2).

**Producers** (`src/stdlib/core/string.ms`), each a look record with `&String` fields and an offset, no allocation:
- `String.split(separator) Split`: `next` calls `msrt_string_split_at(text, separator, at)` (already in the runtime, now with an `ms-sig`), advances by piece plus separator, ends one past the text for a nonempty separator, as `source_split` does.
- `String.lines() Lines`, `String.fields_by(is_separator) Fields`: the same walk over line ends and separator runs.
- `String.chars()` is out of scope here: its walk already lowers without a list (`for c in text.chars()`).

**Adapters** (`src/stdlib/core/iter.ms`, generic records over `I Iterator[T]`): `Mapped`, `Filtered`, plus `take`, `skip`, `enumerate` in a later stage. One carrier, `Seq[I, T]`, holds the source and declares the chain methods once: `map`, `filter`, `take`, `skip`, and the consumers `fold`, `sum`, `count`, `any`, `all`, `find`, `for_each`, `collect`. Every producer returns its own record, which converts with `seq()`; `Split`, `Lines`, `Fields` and `List.iter()` declare `map`, `filter`, `collect` and `seq` and forward to `Seq`. `collect()` clones owned items; `Split.collect()` and `Lines.collect()` call the existing list-building natives from the current offset, so a list of views costs what `split` costs today.

**Lists.** `List.map` and `List.filter` return `Mapped` and `Filtered` over a `ListIter` (`fn hold List[T].iter()`); `for x in list` keeps its direct loop. The eager forms become `.collect()`.

**Ownership.** An iterator is a look: it freezes its sources (`text`, a list), cannot be cloned, stored in an owned field, sent over a pipe, or outlive the source. A closure parameter of `map` receives the item as a borrow, as a list callback does. `collect()` of looks needs `Clonable` items or the view-list natives above; a `List[String]` that must own its pieces writes `.map(p => p.clone()).collect()`.

**Compiler fixes needed first** (general, with their own fixtures):
- A call to an interface operation on a bound type variable (`self.source.next()`, `I: Iterator[T]`) passes a `var` receiver through its slot like any `var` method; `lower_call.c` treated only interface-typed receivers that way.
- A record built from a type-variable field is a carrier when the instance names a look (`Mapped[Words, ...]`), so a chain returned from a function or method is tied to the held source (`own/look_fields.c`).
- Open, filed as an issue: `p := t.view(a, b); return p` in a `&String` function fails MIR verification (the scope owns the local). Producers avoid a view local until it is fixed; the workaround is removed with the fix.

**Edge cases.**
- Empty text: `"".split(",")` yields one empty piece; `"".lines()` yields none; an empty separator cuts by scalar, as today.
- A source changed during the walk is rejected by the borrow rule (`text is frozen by the iterator`).
- A fault in a callback unwinds the iterator, which owns nothing.
- Closures that capture a `var` mutate it in step order, per item, not per stage (order of side effects differs from the eager chain; Rust has the same rule).

## Fit with the language

- **Memory model:** one owner, no hidden copy; items are borrows, `.clone()` and `.collect()` are the explicit copies.
- **Agent ergonomics:** the old call sites fail to type-check with "expected List, found Split"; the fix is `.collect()` or a `for`. `ms fix` is not needed: the rewrite is mechanical.
- **Names:** `collect`, `map`, `filter`, `fold`, `take`, `skip` follow Rust; `Seq` is the only new type name seen in diagnostics.
- **Platforms:** no change; pure `.ms` over existing runtime natives.

## Measured benefit

Hypothesis (the per-item call already costs 5 to 11% more instructions in the split loop, so wall time decides), to measure per stage against the latest dated baseline in `bench/perf/results.md` (min of 9 and callgrind): `wordfreq`, `report`, `grep`, `pargroup` move toward Rust; no program regresses, including `closures_20M`. The `for`-over-`split` loop must match the current offset walk, since both call `msrt_string_split_at`. Stage 3 deletes `source_split` and the scalar fusion lowering only if the new form is at least as fast; otherwise they stay and the gap is a bug to fix at the root.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/lower/lower_call.c`, `own/look_fields.c` | bound `var` receivers; carrier through a type variable | `e2e/accept/bound-var-operation`, `look-chain-returned` |
| `src/stdlib/core/string.ms`, `core/iter.ms`, `collections/collections.ms` | producers, adapters, `Seq`; `split`, `lines`, `fields_by`, `map`, `filter` change type | conformance fixtures, stdlib tests |
| `src/runtime/core/string_split.h`, `src/stdlib/internal/string.ms` | `ms-sig` and declaration for `msrt_string_split_at` | `ctest` |
| `src/compiler/lower/lower_for.c`, `opt/opt_fuse.c` | delete `source_split` (stage 3) | `lint`, `conform`, perf runs |
| callers: stdlib, `bench/`, `examples/`, `documentation/`, `tests/` | `.collect()` or a `for` | `make verify-full` |
| docs, wiki | loops guide, text guide, iterators page | `docs-check` |

## Compatibility

Every use of `split`, `lines`, `fields_by`, `map`, `filter` and `flat_map` as a list needs `.collect()`. About 700 `.split(` and 1,400 `.map(`/`.filter(` hits in the repository, docs included; a script cannot tell a stored list from a `for` source, so the rewrite is driven by compiler errors, with a build after each batch. External programs get a type error naming the fix. No other API changes.

## Alternatives considered

- Do nothing: keep the two special cases; `lines`, `fields_by` and string chains keep the list cost.
- Compiler-only lazy lowering of more shapes: more name-keyed cases, no change for user iterators; the owner rejected compiler magic for these.
- A boxed `Iterator[T]` interface for chains: one type, but a virtual call per item and a vtable per adapter; loses the inlining that makes the loop match C.
- Keep `List.map` eager and add `iter().map()`: no break for lists, but two ways to write the same chain.

## Stages

Skeptical review (2026-11-25): go with changes. The measured gaps are real (`bench/perf/results.md`), but most of them are page faults from lists that `for` reads once, so the text producers come first and the `List.map` and `List.filter` break waits for their numbers.

1. Compiler fixes (bound `var` receiver, carrier through a type variable) with fixtures. Gate: `ctest`, `conform`.
2. Prototype lazy `fields_by`, `lines` and `split` as look records, measure `wordfreq`, `grep`, `report` and `pargroup` (min of 9, callgrind) against the current numbers. Go on only if none is slower; the per-item `next` through `&String?` must inline to the current offset walk.
3. Migrate callers (`.collect()` or a `for`; counted with `grep -F`, about 700 `.split(`), delete `source_split`.
4. Next stage, not conditional (lazy is the default design, `.collect()` the opt-in); it ships once the adapter form matches the fused loops, and a gap is fixed at the root: `Seq`, `Mapped`, `Filtered`, lazy `List.map` and `List.filter` (about 1,400 call sites), then retire the scalar fusion lowering.

## Open questions

- Does `collect()` on an iterator of looks yield `List[&String]` (cheap, the type `split` returns today) or `List[String]` (owned)? Recommend views while `List[&T]` cannot be built in `.ms`, and `.clone()` through `map` for an owned list.
