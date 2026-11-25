# A signature states what happens to each argument

* Status: **Approved by Chinmay 2026-11-24, implementing** (checked against `54bac8d7`)
* Authors: [chinmaymk](https://github.com/chinmaymk)
* Implementation: stages 1 to 3 merged ([#6900](https://github.com/manuscript-lang/manuscript/pull/6900), #6908, #6909, #6910, #6913); stage 4 in [#6916](https://github.com/manuscript-lang/manuscript/pull/6916) except the native name list; stage 5 not started
* Supersedes / Extracted from: result-borrow inference in [borrowed-parts](borrowed-parts.md) rule 2; the body-less rule in [borrowed-results](borrowed-results.md)
* Direction: Chinmay, 2026-11-24: "functions need self-sufficient signatures: a signature states everything a caller needs; bodies are checked against signatures, never read by callers"; one word means one thing; two questions, two marks (how long to keep the memory, owned or reference); remove result `move`; no copy-on-write; no reference counting; scoped to signatures, fields, iterators and interfaces (shared handles, pools and tasks come later). Advice from a Fable review shaped `&T` as a type form.

## Summary

- Problem: three facts about a call are read from bodies: whether a callback parameter is kept, whether a result is a part of an argument, and (until #6900) whether a parameter is taken. A caller, an interface, a function type and an agent cannot see them.
- Change: two marks answer two questions. On an argument, `hold` says the result keeps using it. On a type, `&T` says a value is a reference to a `T` owned elsewhere (a look). An unmarked result is a new owned value; result `move` is deleted. The body is checked against the signature.
- Decision requested: approve `hold` on arguments, `&T` as a type form, and the removal of result `move`.

## Rules

1. A plain `T` is owned by whatever holds it; `&T` refers to a `T` someone else owns. Scalars copy, and `&` of a scalar is an error.
2. An argument mark says what the callee does with it: nothing reads, `var` changes, `move` takes, `hold` lets the result keep using it.
3. A `hold` argument is frozen (no change, reassignment or move) until the result's last use.
4. A `&` in a result comes only from `hold` arguments, per component, on every path. An unmarked result is a new owned value.
5. A reference cannot outlive its source: it cannot be stored in an owned place, captured by an escaping closure, passed to `move`, or sent over a pipe. `.clone()` is the only copy.
6. A signature is the whole contract: callers read only it, each body is checked against its own, and interfaces and function types carry the same marks positionally and match exactly.
7. A type is a look if it contains `&` (a `&T`, a `&` field, a container of looks); the same limits apply to it.

## Motivation

Memory has three properties: who frees it, whether it can change, and how long a use lasts. A signature can already say read, change and take. It cannot say "the result keeps using this argument", the one cell of the grid that crosses a call. The compiler guesses it from the body (`own/result_borrows.c`, `own/escapes.c`), and guessing fails exactly where the body is not visible.

Measured at `54bac8d7` (temporary counters, `ms check` per file, deduplicated):
- Bodied stdlib functions: about 45 return a part of an argument; the corpus (tests, bench, tools, docs, examples) has 367 of 11,503.
- Callback parameters the body keeps or holds (`escapes.c`): about 20 in the stdlib and 37 in the corpus.
- Result `move`: 359 stdlib lines (318 body-less natives), 2 in the corpus. One word, `move`, means "ownership leaves" on parameters and "new value" on results.

```manuscript
type Person {
    name String
}

fn Person.name_of() String {
    return self.name
}

fn mixed(p Person, fresh Bool) String {
    if fresh {
        return "new"
    }
    return p.name
}
```

`ms check` on `mixed`: `this function returns a reference into its arguments at 13:14 but a new value here; return .clone() of the part there, or build a new value on every path`. The diagnostic exists only because the signature cannot say what the function does.

## Proposed solution

Two questions, two marks.

1. **What happens to this argument?** Nothing reads it, `var` changes it, `move` takes it, `hold` lets the result keep using it (frozen until the result's last use).
2. **Is this value a reference or owned?** `&T` is a reference to a `T` owned elsewhere. `T` is owned by the slot that holds it.

```manuscript
// proposed; `hold` and `&T` do not parse yet
fn List[T].length() Int
fn var List[T].append(move value T) Void
fn hold List[T].first() &T?                      // a reference into the list
fn List[T].first_copy() T?                       // a new value
fn pick(hold a Person, b Person) &String         // into a, not b
fn hold String.split(sep String) List[&String]   // a list of references
fn hold parse(src String) Result[&String, Error] // payload looks, error owned
fn promise(hold work fn() Int) Promise[Int]      // Promise is a look type
fn(hold List[Int]) &Int?                         // function types carry both
```

`&T` is an ordinary type form: in results, type arguments and record fields (`items &List[T]`). It is never written at the top of a parameter type (the mode says it) or at a call site. A call result holds every `hold` argument; a result with no `&` in its type and no look type holds nothing.

## Detailed design

**Syntax.** `hold` sits where `move` and `var` sit (a following `[` makes it a name, as in `fn hold[T](slot Int)`): before a parameter name, after `fn` for a receiver (`fn hold List[T].first()`), before `fn` in an interface (`hold fn first() &T?`), before a parameter type in a function type. A lambda takes its modes from the expected function type. It is a word only when a name or type follows, so `hold[T](slot Int)` in `net/router.ms:927` still parses. `hold` cannot combine with `move`. `var` and `hold` stay independent: `fn var hold Cache.get(key String) &V?` changes the cache during the call and keeps it frozen exclusively while the result lives (the LRU case). Result `move` is deleted everywhere, including function types and lambdas (`parse_type.c:210`, `parse_primary.c:374`); `lower/lower_temp.c:58` reads the type instead.

**Calls.** The checker reads only the callee's signature. Each `hold` argument is frozen (no change, reassignment or move) until the last use of the result. A look cannot be stored in an owned place, captured by an escaping closure, passed to `move`, or sent over a pipe. A `hold` argument that is a temporary lives to the end of the statement, so its result cannot outlive it (`references.md`: move the whole temporary or clone). Moving a part out of a held argument is an error. A `&String` is accepted where a read-only `String` parameter is; `List[&String]` is a different type from `List[String]` (pointers, not owned elements), so `.clone()` each element to convert. `&` normalizes: `&&T` is `&T`, and `&` of a scalar is an error (scalars copy). A temporary `hold` argument lives to the end of the statement; a `for` header or `match` scrutinee lives across the loop or match body, so `for s in make().split(",")` works and `x := make().first()` does not.

**Bodies.** Each body is checked against its own signature:
- Every `&` component is built only from `hold` parameters, per component. `ok(part)` beside `error(new)` is fine when the type says `Result[&T, Error]`; one component that is a part on one path and fresh on another is an error whose fixes are `.clone()` the part or make the fresh value a `hold` argument.
- A `&` result needs at least one `hold` parameter; a part of an unnamed parameter or a local is an error with the fix `.clone()` or `hold`.
- A `hold` parameter no `&` result component uses is a lint, unless the result is an opaque handle that declares it. `hold` is also allowed with no `&` in the result (`promise` keeps its callback; the result type is an opaque stdlib handle), and then only freezes. `hold` on a parameter whose type owns nothing (`Int`) is an error. `hold` on a bare type parameter always freezes; `List.map` stays `fn(T) U` and owned, so no result depends on an instantiation. `&T` is read-only unless the sole `hold` source is `var`; two `hold` sources of which one is `var` is an error.
- A plain parameter is read-only. Storing, returning or capturing it in an escaping closure is an error whose fix is `move` (resource and generic parameters, #6900) or `.clone()`. `x or d` can return `d`, so `get_or` holds both.

**Callbacks.** A function is not an owned value (owner, 2026-11-25), so a parameter of function type takes no `move`, no `hold`, and `&fn` does not exist; writing one is an error. Whether a closure owns its captures is decided from what the callee does with the function (`kept` and `held` in `escapes.c`, extended so a function parameter handed to a callee that holds it in a kept result is kept) and from the result's fate (`result_escapes`), as `promise.ms:260` documents: `return promise(fn: ...)` owns, a promise waited locally borrows. An extern function keeps every function it is handed. The inference stays for function types only; it never decides a result borrow.

**Interfaces and function types.** Modes and `&` are written positionally and must match exactly, as `var` and `move` do today. A call through a function value or interface whose result type contains `&` uses the borrowed-result ABI, which `references.md:28,84` ("always owns its result") and the static `ret_borrowed` reads in `lower_closure.c` and `lower_call.c` currently exclude; both change, and `&Iface` results go through the existing interface-view wrapper (`owned-interface-views.md`). An implementation that computes a fresh value cannot meet an operation returning `&T`; it returns a clone through a wrapper. A call through either owns its result unless the type contains `&`. Using a `hold` function as a plain function value is rejected, as `relays.c` does today.

**Lowering.** `ret_borrowed` is the type containing `&`, no longer derived from a body walk (`lower_func.c:345-362`). Combinations the ABI cannot honor (a `&` result with a `move` parameter, a `&T?` over a boxed Optional) are check errors, not silent copies; per-component looks in `Result[&T, Error]` need the result ABI to carry which component borrows, since `MS_RESULT_BORROWED` today means every path. Both are stage 2 work with fixtures. `lower_temp.c:58` and the gate below use the predicate "type contains `&`".

**Natives.** A body-less declaration in `src/stdlib/*.ms` writes `hold` and `&` like any function; the `@borrows` comments in `src/runtime/core/*.h` and the name list `native_result_borrows` (`result_borrows.c:440`) are deleted. The `"get"` accessor list in `ms_own_native_get` is a separate fact and stays.

**Borrow-pass gate.** `ms_own_borrows` runs only when the stdlib declares a result `move` (`borrows.c:733`); it becomes "the stdlib declares any `&` result", with a reject fixture proving it fires.

**Diagnostics.** `` `name_of` returns part of `self`; write `fn hold Person.name_of() &String` or return `self.name.clone()` ``; `` `pick` says `hold b` but no `&` result uses it ``. A migration command adds `hold` and `&` and deletes result `move` from the old analysis.

## The wider model: one rule for every kind of look

A call result that keeps using an argument, a record field that keeps using a value, an iterator over a list and an interface value wrapping a part are the same thing: a *look*. A type is a look type if it is `&T`, has a `&` field, or has a look as a type argument; this changes the canonical rule "a type cannot hold a view of another variable" (`references.md:30`) and is stage 5, after the signature work. Looks are tied to their sources, freeze them, and cannot outlive them or be stored, escape, move or cross a pipe; everything else is owned.

1. **Records.**
   ```manuscript
   // proposed
   type Cursor[T] {
       items &List[T]
       at Int
   }
   ```
   Building one ties it to the values given, which replaces the hidden copy in construction; a temporary that ends first is an error.
2. **Iterators, slices, entries** are look types, so `for` and `split` need no special case and allocate nothing. A container of looks (`List[&String]`, `List[Cursor[Int]]`) is a look; `.clone()` each element to keep it.
3. **Interfaces.** Converting a look to an interface value gives a look type; converting an owned value gives an owned one.
4. **Stored callbacks** take the state they change as a `var` parameter instead of capturing it.

**Not allowed, on purpose:** a pointer to a single field, a `&` with no `hold` source, shared changeable state, copy-on-write, hidden copies. Shared handles, pools and task sharing are for later proposals.

## Fit with the language

- **Memory model:** one owner, borrow by default, `.clone()` the only copy, no hidden copies. `hold` and `&T` make the one cross-call borrow visible; defaults are unchanged.
- **Agent ergonomics:** one question per argument. The error names the argument and the fix.
- **Names:** `hold` joins `var` and `move` in the argument slot; `&` is the only reference mark and appears only in types; result `move` is removed, so each word means one thing.
- **Platforms:** no change.

## Measured benefit

No speed claim: code already returning a borrow is unchanged. The gain is that the signature is the whole contract, which unblocks interfaces and function types carrying borrowed results. Code removed (hypothesis, `wc -l`): the interprocedural fixpoint in `own/result_borrows.c` (580 lines in all) and the native `@borrows` column. The per-component check of a body against its signature needs similar dataflow, and the caller-side closure decision (`result_escapes`) stays in `escapes.c`, so the net deletion is smaller than the file sizes suggest. Most of `relays.c` (153) stays. The counts above come from temporary counters and are recomputed in stage 2 with a committed script; the stdlib and corpus figures overlap and are not additive.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/syntax` | parse `hold` on parameters, receivers, interface operations, function types; `&T` in types; drop result `move` | parse and fmt fixtures |
| `src/compiler/check` | validate `hold`; match interface and function types | reject fixtures per diagnostic |
| `src/compiler/own/result_borrows.c`, `escapes.c` | check bodies against declared modes; delete inference | `ctest`, conformance |
| `src/compiler/own/borrows.c` | rewrite the result-`move` gate | reject fixture |
| `src/compiler/natives`, `lower` | drop `@borrows`; `ret_borrowed` from the signature | native table test, e2e |
| `src/stdlib/*.ms`, tests, docs | `hold` and `&` on about 45 stdlib, an unmeasured number of natives and 367 other functions; `move` on about 57 callbacks; 361 result `move` removed | `make conform`, `docs-check` |
| `src/compiler/lower` | `ret_borrowed` and temp rules from the type; function-value and interface ABI | e2e, reject fixtures |
| `documentation/core-language/types/references.md`, functions pages | rewrite "returns a borrow without any marker", "a type cannot hold a view", "always owns its result" | `docs-check` |
| `src/tooling`, `src/lsp`, `extensions/agent-skill` | print and complete `hold` and `&` | existing tests |

## Compatibility

Programs that return a part of an argument gain `hold` and `&`; result `move` is deleted; function parameters carry no mark. The migration command does all three from the old analysis. Until migrated, programs fail with a diagnostic that carries the fix; during stage 2 a written mode wins and an unwritten one still falls back to inference.

## Alternatives considered

- **Stored references or `View[T]` everywhere, ARC, copy-on-write:** rejected earlier in this thread: each reintroduces shared changeable state or hidden cost.
- **Do nothing:** the contract stays in bodies and one word keeps two meanings. Concrete failure: a function type or interface operation cannot return a part of its argument today (`relays.c` rejects such a value), so iterator-like and slice-returning interfaces cannot be written.
- **Argument mark only (`hold`, results unmarked):** the draft before this one. A `T?` result is the same type whether owned or a look, so mixed and nested results, fields and interface matching need special rules. Lost on expressiveness.
- **Consume by default with `&` borrow on parameters:** one symbol on both sides, but 93% of parameters (2,751 sampled) are plain reads and would carry `&` (Rust's compiler had 56%), and an unmarked parameter silently moves.
- **Always owned, clone to return a part:** simplest, but brings back the clones `views.md` removed and a copy per lookup.
- **Rust `&'a T` lifetime names, or Swift `@lifetime`:** more expressive (two sources with different lifetimes), more noise. `hold` plus `&` names sources by argument and covers every case found; labels can be added later if a real case needs two lifetimes.
- **Show inferred borrows in `ms inspect`:** cheap, but interfaces and function types still cannot state it.

## Stages

1. Done (#6900): kept resource and generic parameters must be `move`.
2. Parse and check `hold` and `&T`. Where a mode is written it wins and a body that disagrees is an error. Migration command (not committed; the generator ran from the old analysis). Gate: `make verify`, `make conform`.
3. Migrate stdlib, tests, docs. Gate: same; a no-diff `ms emit` of the stdlib for result `hold`, and a reviewed diff for the few callbacks whose capture mode changes.
4. Delete the body inference and result `move`; rewrite the borrow-pass gate (done). Delete the native name list and `@borrows` once `Map.keys`, `Map.values`, the payload `get` and `List.slice` state their borrows in signatures (open). Gate: same, `make count-check`, a `bench/perf` run against the latest baseline.
5. `&` fields, look records, iterators and interface looks (the wider model, items 1 to 3). Gate: reject fixtures for escape, pipe send and temporary sources; the hidden-copy fix lands first or here.

## Open questions

- The word `hold` (recommended) or `keep`; it is already a function name in `net/router.ms:927`, which still parses.
- `List.slice` borrows only for plain-data elements today (`result_borrows.c:465`), which no signature can say. Recommended: `hold` and `&` for plain-data slices, a separate copying method for owning elements.
- `Result[&T, Error]` needs per-component borrow information in the result ABI; confirm the cost in stage 2 before stage 5.
- Two sources needing different lifetimes (the only case `hold` cannot say): none found in the stdlib or corpus; labels would be added if one appears.
