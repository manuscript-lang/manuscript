# Specialize functions on a known closure argument

## Summary

- Problem: a function that receives a `Callable` calls it with `call.ind` per use, even when every caller passes a known lambda (#1301).
- Change: a new step in the `inline` pass clones a callee per distinct (callee, closure code), binds the closure parameter to a `closure.new` made inside the clone, and lets the existing closure inliner remove the indirect call.
- Cost: one clone per (callee, lambda) pair, bounded by a size limit and a module-wide clone budget. No new syntax, type, IR op, or runtime entry point.
- Decision requested: build it. No user-visible language change.

## Status

Implemented 2026-10-25; measured `list.callable_key` 1 ns/op vs `list.callable_key_loop` 1 ns/op (was about 1.7x). Proposal (skeptical review applied: guards, consumers, precedent and the inline-with-bonus alternative added; `bench/perf` page gets the repro in stage 3), 2026-10-25, checked against `e779cb18`. Direction: "specialize or inline functions that take a known lambda ... so methods like `List.max_by` and Manuscript-bodied stdlib methods match hand-written loops" (#1301).

## Problem

- Measured at `e779cb18` with a `best(xs, key: Callable[[P], Int])` function over 100000 records (scratch bench, `ms run`, release):

  | Variant | Time per call |
  | --- | --- |
  | `best(xs, lambda (p: P) -> Int: p.w * m)` | 135-143us |
  | hand loop with `p.w * m` inline | 77-86us |

  Ratio about 1.7x. #1301 reports 2.7x vs 1.6x for `max_by` on its machine.
- Cause (verified, `ms emit` of the program): the callee holds `copy %key; call.ind; drop` per element and carries the closure through loop block parameters. `inline_closures_in` (`crates/ms-mir/src/opt/inline.rs`) only resolves a `call.ind` whose callee value is the direct result of a `closure.new` in the same function, so it never fires inside `best`.
- `inline_calls` does not help: a callee with a loop is inlined only when called from inside a loop and when it is under `BASE_THRESHOLD` (plus bonuses); real stdlib-style bodies exceed that, and raising it bloats every call site.
- Precedent: `specialize_sort_thunks` already does this for one runtime sort thunk; the general mechanism replaces per-case special-casing (the Manuscript-bodied `sorted()` of #1302 needs one today).
- Consumers: any Manuscript-bodied function taking a `Callable` (user code, `stdlib/streams.ms`, `stdlib/sorted.ms` `for_each`), and `min_by`/`max_by` from #1300 once moved to Manuscript (#1295).
- Non-goals: closures that capture owned values, closure parameters that are consumed (`Own`), recursion through the closure parameter, interface (`call.method`) dispatch, and removing the sort-comparator special case from #1302 (not on main yet; follow up after it merges).

## Design

Rule: a `call @C(args)` in function F, where argument i is a value known in F to be a `closure.new @g caps` (plain-data captures, the existing `inline_closures` condition) and C's parameter i is a borrowed `fn` parameter, is rewritten to call a clone `C'` of C.

- `C'` = clone of C with parameter i removed and one parameter per capture added. Its entry block starts with `%k = closure.new @g caps...` (fresh value) and every use of the old parameter becomes `%k`. Before each `ret`, `drop %k` keeps ownership linear (the old parameter was borrowed, so the caller still drops its own closure).
- Clones are cached by (C, g, i). The caller's call passes the captures in place of the closure; its now-unused `closure.new` is removed by the existing dead-closure cleanup.
- Specialization repeats to a fixpoint (clone-of-clone when `C'` forwards `%k` to another call), capped at a few rounds.
- Then `inline_closures_in` handles the body. It is extended to see through closure aliases:
  - `copy` of a known closure.
  - A block parameter whose incoming arguments are all the same known closure or the parameter itself (loop-carried).
  - Dead-closure cleanup deletes the `closure.new`, alias copies, drops, and the invariant block parameters with their incoming arguments when every use in the alias class is a `copy`, `drop`, branch argument into the class, or an inlined `call.ind`.
- Guards (checked at the call site): parameter i has `Mode::Borrow` (an `Own` parameter is skipped); every capture is `!needs_drop`; the `closure.new` is the direct definition of the argument (aliases are not specialized in v1, so captures dominate the call); at most one closure argument is specialized per rewrite, and further ones are handled by the fixpoint; closure code is at most `BASE_THRESHOLD` instructions, the same limit `inline_closures_in` applies, otherwise nothing is gained and no clone is made.
- `Term::Fault` needs no `drop %k`: the verifier requires drops only at `ret`. Generic functions are monomorphized before MIR, so clones see concrete types. Recursion through `call.ind` is not a direct cycle but cannot be reached with a known closure at the clone's own call, so it is safe; direct cycles are skipped.
- Budget: clone instructions count against `SPECIALIZE_BUDGET` (module-wide) and the per-caller `GROWTH_FACTOR` budget is untouched since the caller only changes its call. Rounds are capped at 4.
- Limits: C is `FuncKind::Normal`, not `inline(never)`, not on a direct-call cycle, at most `SPECIALIZE_MAX_SIZE` instructions, and the module may gain at most `SPECIALIZE_BUDGET` clone instructions. A clone whose closure never gets inlined is a waste but is correct (it materializes the closure exactly as the caller did).
- Semantics: no observable change. The key is still called once per use, in order. Faults, cleanup order, and cancellation behave as before because the clone body is the callee body with the same instructions; a `drop` of a closure object has no observable effect.

Before/after for `best` called with `lambda (p: P) -> Int: p.w * m`: the call becomes `call @best.spec(xs, m)` and the loop body contains `rec.get P.w` and `imul.chk` with no `call.ind`, `copy`, or `drop`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/opt/inline.rs` | `specialize_closure_args` step before `inline_calls`; alias-aware `inline_closures_in` and cleanup | `crates/ms-mir/tests/opt_inline.rs`: clone created and indirect call gone, loop-carried closure, captured value, two different lambdas, shared lambda reuses clone, owned capture left alone, recursion left alone, interpreter result equal before/after |
| `bench/perf/stdlib/src/lists.ms` | none for this change (no `max_by` on main yet); `bench/perf/` page gets a dated section with the scratch comparison | `make stdlib-bench` rerun |
| `ms-lower`, `ms-clif`, `ms-rt`, stdlib, formatter, LSP, docs | unchanged | `make conform`, e2e |

## Alternatives

- Do nothing: leaves every Manuscript-bodied higher-order function at 1.7x or worse, which blocks moving `min_by`/`max_by` and similar methods out of Rust (#1295), against the Manuscript-first rule.
- Raise `inline_calls` limits so the callee is inlined whole: bloats every call site, and a loop callee would still need the closure alias handling. Rejected as the primary mechanism; it composes with this when the callee is small.
- Devirtualize only (`call.ind` to `call @g(env, ..)` in a clone, keep the closure object): leaves `closure.cap` loads per call and no inlining across the key, so it cannot reach hand-loop speed. Rejected.
- Inline a loop callee at call sites that pass a known closure (a `CONST_ARG_BONUS` analogue): no clone cache, but duplicates the body at every call site and fails once the callee exceeds the growth budget. Needs the same alias handling. Rejected for growth; it composes since the clone can itself be inlined by `inline_calls`.
- Pass captures through in the caller only (inline the callee at the call site): same limits as raising thresholds.

Drawbacks: code growth per distinct lambda passed to a large function; bounded by the budget.

## Staging and verification

1. Alias-aware `inline_closures_in` and cleanup, tested on hand-written MIR. Gate: `cargo nextest run -p ms-mir`.
2. `specialize_closure_args`, tests above. Gate: ms-mir tests, `make conform`, e2e, `cargo clippy`, `cargo fmt`.
3. Rerun the scratch comparison and the `bench/perf` suite; go/no-go: callable variant within 1.2x of the loop and no regression in existing stdlib benchmarks or binary size beyond noise.

## Open questions

None; no language or user-visible change.
