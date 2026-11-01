# Primitives copy, everything else is a reference with one owner

## Summary

- Problem: the ownership rules depart from the habits of Python, Go and TypeScript in ways that cost agents most of their first builds (#2147): `var y = xs[0]` writes through (#2168), `let b = a` of a list used later is a move error, a getter cannot return a field without `.clone()`, and `if var x = m.get(k)` changes a copy with no signal (#2164).
- Change: primitives copy; strings, records and collections are references to one owned value. A name bound to a place, to another name or to a result derived from an argument borrows it (`let` shared, `var` exclusive), arguments are borrowed, and lending results are inferred from bodies. `.clone()` is the only copy a program writes. No keyword, no refcount, no GC.
- Decision requested: approve the rules and ship them as one PR. They reverse `proposals/remove-ref.md` (approved 2026-10-31) and the "records of scalars copy" clause of `crates/DESIGN.md` decision 1.

## Status

Implemented in the same PR (checker, lowering, MIR verifier, stdlib, docs); the sections below are the design as proposed. Proposal, 2026-11-01, checked against `a0f61d32`. Direction (Chinmay, 2026-11-01): "reference semantics but with ownership and borrow rules, no reference counting; numeric copied out, records and strings referenced; only copy happens via `.clone()`; everything returns references except primitive types; records are effectively containers of data; `let` should not freeze, keep [mutation under a live `let`] as error; do everything as one PR; bulletproof correctness". Two skeptical reviews applied (lending temporaries held, no address-returning lenders, `Shared.get` excluded, defaults and lambdas never lend, inference flip named). Reverses: `remove-ref.md`; `DESIGN.md` decision 1 (records of scalars copy; "a result owns its value"); `OWNERSHIP.md` Partial moves and Mutable borrows; `documentation/core-language/basics/bindings.md:80`; `types/references.md:14-19`; `wiki/language/ref-is-removed-results-and-fields-own-their-value.md`; `one-borrow-model.md` stage 2 (reinstated without the keyword).

## Problem

- Measured (`bench/agent/results/trials-2026-10-31.jsonl`): Manuscript 8/20 first builds against Go 18, Rust 16, TypeScript 18. The diagnostic counts in #2147 come from transcripts that are not committed.
- Verified with `ms check` and `ms run` built from `a0f61d32` (`make build`, scratch programs `d.ms`, `b.ms`, `c.ms`):

```manuscript
var a = [1, 2]
let b = a                         # error: `a` is moved here but used again at 8:5
a.append(3)                       # (OWNERSHIP.md "Borrows are lexical" says `let y = x` borrows)

impl Row:
    fn title() String:
        return self.name          # error: cannot move `self.name` out of `self`: only a whole variable can move

fn count(var seen: Map[String, Int], r: Row) Unit:
    seen.add(r.name, 1)           # accepted: a partial move, so `count` consumes `r`
count(var seen, rows[0])          # error: cannot move `rows[..]` out of `rows`; fix printed: `rows[0].clone()`

var y = xs[0]
y += 10                           # prints 11 11 (#2168)
if var q = m.get("a"):
    q.append(1)                   # m unchanged, no diagnostic (#2164)
```

- Non-goals: two owners of one value (`Shared[T]` stays the only way), the `var` marker at declarations and calls, lending from `Shared.get` beyond its expression (`OWNERSHIP.md` Model, `wiki/language` Shared pages), lending through function values and lambdas (`one-borrow-model.md` stage 5: an escaping closure owns its captures).

## Design

**Rule: a primitive copies; every other value has one owner, and every other name, argument and derived result is a reference to it, shared through `let` and exclusive through `var`; `.clone()` is the copy a program writes.**

Values:

- Primitives copy: `Int`, `Float`, `Bool`, the fixed-width numbers, `Unit`, alternatives whose payloads are all primitives (`Int?`), and handles that copy by design (`Shared[T]`, natives declaring `impl Copy` such as `Decimal`). `var y = xs[0]; y += 10` leaves `xs[0]` alone; the scalar write-through exception (`bindings.md:80`) is deleted. `if var n = counts[key]?` stays an in-place borrow: `?` names the entry.
- References: `String`, `Bytes`, records (whatever their fields), alternatives with a non-primitive payload, collections, closures, interface values. `Class::Copy` no longer covers a record of scalars (`classify.rs` `nominal`): `var ps = [p]; p.x = 5` is a move error with the `.clone()` fix.
- Remaining copies the language makes without `.clone()`, unchanged: an interface conversion of a borrowed value (`OWNERSHIP.md` Interface conversion), a function value that keeps a lent argument (`require_clonable`), a lending call on a temporary (the part moves out of the dying temporary; no allocation). Each stays listed in `OWNERSHIP.md`.

Bindings:

- `let b = a`, `let x = a.b`, `let x = xs[i]`, `let n = f(a)` where `f` lends: shared borrows. Changing, reassigning or moving the origin while the binding is still used is an error (today's rule, `check_change`), with the fix "use `b` before this, or end its initializer with `.clone()`". Today a bare name on the right is consumed (`bind`, `Demand::Consume`); it borrows instead.
- `var b = a`, `var x = a.b`, `var x = xs[i]`: exclusive borrows; `var c = a; c.append(4)` changes `a`, and `a` cannot be read, changed or moved until `c`'s last use. Reassigning a borrow stays rejected (`var s = r.name; s += "!"`: "cannot reassign `s`").
- `var xs = f(b)` where `f` lends one field path of one argument or receiver (`return self.items`): an exclusive borrow of that place, lowered by path substitution (`getter_borrows`, `alias.rs`), so `xs.append(1)` changes `b.items`; `b` must be a `var` binding. A lender with two paths or two origins bound with `var` is rejected: "bind it with `let`, or borrow the field `var xs = b.items`". No lender returns an address: `var` parameters are take/put through a frame slot (`DESIGN.md` value representation), so an address would dangle.
- A binding of a literal, constructor, `.clone()` or non-lending call owns, as today.

Results:

- A bodied function lends when every `return` yields a part of a parameter or receiver: a field path, an element, a payload (`some(x.f)`, `x.f?`), or a lending call applied to one. Owned paths: a literal, constructor, `.clone()`, a non-lending call, a part of a temporary, of a default argument, of a closure capture or of a local. A function with both kinds of path is rejected at the owned `return`: "returns a part of `b` elsewhere; return `b.items.clone()` here, or build a new value on every path". Lambdas, function values and interface operations never lend; an implementation of an interface operation that returns a part writes `.clone()` (unchanged).
- Inference is a program-wide fixpoint over the existing `Summary` (`modes.rs`): every bodied candidate starts as lending, a candidate with an owned path is withdrawn, repeat until stable; recursive and mutual lenders converge because withdrawal is monotone. Natives keep today's shape rule for lending container reads (`accessor` in `modes.rs`, lowered in place per `wiki/compiler/lowering-lends-what-the-checker-already-holds-as-a-borrow.md`); `Shared.get` lends only within its expression, as today.
- A lending call is a borrow of its lent arguments' origins wherever the checker asks for origins: the binding it initializes, a loop or match scrutinee, overlap (`g(var b, f(b))` is rejected), and the statement's temporaries. `pure_origins` returns them for calls (today it returns `None`, `walk.rs:1634`).
- Accepted risk: a body edit in one module that turns a fresh result into a part makes `var xs = f(b)` in another module write through where it copied before, and `let x = f(b); b.change()` an error. The first is the behavior the caller asked for by writing `var`; the second is a diagnostic, not a memory bug.

Lost changes:

- `if var x = e` where `e` is an owned `Optional`/`Result` read from a container (`get`, `first`, `last`, `pop`) with a record or collection payload, `x` is changed by a mutator or field store, and `x` is never read, stored or returned afterwards (per-place liveness, `live.rs`): error "the change to `x` is lost: `x` owns a copy; borrow the entry with `if var x = m[k]?`, or store `x` back". Resources and `var fn` calls with effects (`close`) are not changes for this rule.

Proposed behavior (unchecked: rejected at `a0f61d32`):

```manuscript
fn label(r: Row) String:
    return r.name                 # lends from `r`

fn grow(var b: Box) Int:
    var xs = b.items()            # exclusive borrow of b.items (one field path)
    xs.append(1)                  # b.items changes
    let n = label(b.row)          # shared borrow; b.row cannot change until n's last use
    return b.items.length() + n.length()
```

Soundness (hypothesis until the gates below pass):

- A borrow never outlives its origin: lexical, ends at the holder's last use, never stored (`Ownership.borrows`).
- The origin is frozen while a borrow lives, exclusively for `var`; a lending call's result counts as a borrow of its origins everywhere a place borrow does.
- A lent result derives only from parameters: checked in `walk.rs`, and again by a MIR verifier rule that a lending function's `ret` is reached from a parameter through loads and field/element reads only. The four use-after-free paths of `one-borrow-model.md` (lending a copy of a scrutinee, a loop iterable, a `let`, or a default argument) are verifier failures.
- Write-through never produces an address: path substitution names the caller's own place.
- Lent values are never dropped by the caller (`Func.ret_borrowed`, no `Drop` on a lent `ret`; `lastuse` treats a lent binding as pointing into its origin).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `ownership/classify.rs` | records never `Copy` | corpus; conformance fixtures that copy records re-recorded |
| `ms-check` `ownership/walk.rs`, `modes.rs`, `mod.rs` | `bind`: name borrows, scalar `var` copies; `Summary.result` lending fixpoint; `pure_origins` for lending calls; mixed-path, `var`-of-multi-path and lost-change errors; `getter_borrows` filled | fixtures: `let_name_borrows`, `var_name_exclusive`, `lender_field`, `lender_element`, `lender_payload`, `lender_recursive`, `lender_mutual`, `lender_mixed_paths`, `lender_default_owns`, `lender_temporary_owns`, `lender_overlaps_var_argument`, `lender_loop_mutates_origin`, `lender_through_borrow`, `lambda_never_lends`, `var_of_two_path_lender`, `if_var_lost_change`, `if_var_close_is_not_lost` |
| `ms-mir` `ir.rs`, `verify.rs`, `lastuse` | `Func.ret_borrowed`; verifier rule above; no drop of lent results | `verify` tests, `opt_lastuse.rs` |
| `ms-lower` `func.rs` (`bind_local`), `stmt.rs`, `call.rs`, `alias.rs` | bind from `Ownership.borrows`, not op shapes (a `let b = a` must not copy); lending instances return the words without ownership; `getter_borrows` substitution | `make count-check` pairs (`let_name_borrows` equals the no-binding program; `remove-ref.md` pairs return to their `ref` counts), `make leak-check` |
| `stdlib/*.ms` | delete `.clone()` on returned parts; `Set[P]`/`Map[P, V]` inserts of plain records move or clone | stdlib e2e, `make conform` |
| docs and wiki | `bindings.md`, `references.md`, `collections.md`, `grammar.md:24`, `OWNERSHIP.md`, `DESIGN.md` decision 1, `ms guide`; rewrite `wiki/language/ref-is-removed-...md`, update `wiki/compiler/lowering-lends-...md` | `make docs-check`, `make repo-check` |

## Alternatives

- Do nothing: sound today; the cost is an unmeasured share of a 60% first-build miss rate and three open issues that are "by design".
- Copy implicitly (plain data copies, drafted first): hidden allocations and silent divergence from aliasing habits; rejected by the user.
- Explicit `ref` in signatures (`remove-ref.md` Alternatives): documents lending and avoids the body-edit flip, at the cost of the keyword the user removed as confusing.
- Address-returning lenders for `var xs = f(b)` with several paths: unsound with the take/put `var` convention; path substitution covers the one-field-path case, which is every getter.
- Reference counting or a tracing GC: gives up deterministic drops; excluded by the user.

## One PR, in order

Each step lands in the same PR; `make verify-full`, `bench/perf` against `bench/perf/baseline-2026-10-28.md` and `ms check` time on the stdlib are recorded in the PR before merge.

1. Bindings: scalar `var` copies, name borrows (checker and `bind_local`), records never `Copy`; fixtures, docs.
2. Lending results: fixpoint, `pure_origins`, freezes, mixed-path error, `ret_borrowed`, verifier rule, lowering of lent returns, stdlib `.clone()` sweep.
3. `var xs = f(b)` by path substitution (`getter_borrows`), `var`-of-multi-path error.
4. Lost-change error, diagnostic rewrite, `ms guide` example.
5. Gates: ownership corpus with one fixture per use-after-free shape (above); conformance; `leak-check`; valgrind over the corpus run natively; differential Debug (Cranelift) versus Release (LLVM) run of the corpus comparing output and `count-check` allocations; a mutation run of `ms check` over the accept corpus (each accept program with one statement deleted) expecting no verifier failure; an adversarial review of lowering for dangling or double-dropped lent values; Haiku agent bench rerun with the first-build rate recorded in `bench/agent/results`.

## Open questions, resolved while implementing

- Interface operations own their results (an implementation that returns a stored field writes `.clone()`): a call through the interface cannot know which implementation runs. A type's own methods (`impl T:`, checked as a synthesized interface) lend like functions.
- A lender through a `var` parameter or `var fn` receiver is accepted for `let` results (`fn f(var a: Acc) List[Int]: return a.items`): the result borrows the frozen argument and nothing returns an address.
- Resources never lend: `return r` of a `Closeable` hands it to the caller, which closes it.
- An argument converted on the way in (an `Optional` wrap, a widened error, an interface) is a temporary, so the call's result is owned and copied before the temporary drops.
