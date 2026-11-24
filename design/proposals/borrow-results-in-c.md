# Borrowed results: a function returns the part it borrowed, and no copy is hidden

## Summary

- Problem: with `implicit_clone_is_error` on, 503 of 1311 fixtures fail lowering; 456 of them because a function returns a borrowed parameter or a part of one (`fn id(b: Big) Big: b`, `return self.name`) and the callee clones it. Chinmay's rule: no hidden copies in the compiler; `.clone()` is the only copy a program writes.
- Change: infer which callables return a borrow (`returns_borrow`), lower them with `MirFunc.ret_borrowed` and no copy at `return`, and bind a call's borrowed result as a borrow, holding the temporaries it borrows from for the statement. The MIR half already exists.
- Decision requested: none for the language; this implements `design/proposals/reference-ownership.md` ("borrowing results are inferred from bodies") and `design/proposals/borrowed-results.md` in the C port.

## Status

Proposal, 2026-11-22, checked against `21ca3a16c9`.

## Problem

- Verified with `ms emit` on `tests/conformance/fixtures/e2e/accept/borrow-whole-temporary.ms` after flipping the flag: `a value is copied ... while lowering id`, from `take_ownership` (`lower_expr.c`): a borrowed parameter used as a returned value is cloned.
- Sweep over all 1311 fixtures, first error per file: 468 in `take_ownership`'s final clone (456 are a borrowed parameter, 10 a local, 2 a member), 20 in `lower_list.c` list-literal elements, 7 closure captures, 5 natives, 3 statements.
- The C port has no borrowing callable fact: `grep returns_borrow src` is empty. `own/borrows.c` infers a borrow per call for the borrow check (`borrows_from`) but nothing reaches lowering. MIR is ready: `ret_borrowed`, `mir_result_mode` (a call to a `ret_borrowed` function yields a borrow), the verifier rejecting an owned return from one, inlining.

## Design

**Rule: a function borrows when every `return` yields a part of a parameter or receiver; its caller borrows the result from the arguments' origins.**

- Fact: a per-callable `borrows` bit, module-qualified like `kept` in `own/escapes.c`, derived from the relation the checker already uses: `returns_part_of` and `borrows_from` in `own/borrows.c` (a callee's returned values rooted at parameter N; natives borrow unless the result is declared `move`, #6125). Lowering must read the same relation as the borrow check, or a `ret_borrowed` function and a checker that thinks the result owns would disagree and leave a dangling borrow. So the work is to promote that code to a per-callable result, not to write a second inference.
- Gaps to close while promoting it (review): the walk is depth-capped at 4 and 16 returns, and per argument; a self-recursive `return f(x)` must not count as borrowing; the bit is keyed per generic instance and per module.
- Lowering: a borrowing callable gets `ret_borrowed`; `return` of a borrowed path emits the reference without `fn_implicit_clone`. A call to a borrowing callable is bound borrowed: `x := id(b)` borrows `b`; a consumer that needs an owner (a `move` parameter, a stored value) is the checker's error unless the source says `.clone()`. A borrow from a temporary (`id(mk(3))`) moves the part out of the dying temporary, no allocation.
- One fact for three owners: own/ computes `borrows`; the checker's borrow pass and `own/borrows.c` read the same bit instead of `borrows_from`; lowering reads it.
- Remaining sites after this: 20 list-literal elements and 7 closure captures (loop element, borrowed parameter, reassigned `var`), each needing a move or a source `.clone()`.

## Risks and the gate

- `ret_borrowed` has no producer in `src/` today (only consumers: `mir_analysis.c`, `mir_verify_own.c`, `mir_depth.c`, `opt_inline.c`); the Load/Store return path of `mir_depth` has never run on real output. Prototype first: set it on one function and run `borrow-whole-temporary.ms`.
- Caller side: `x := id(b)` becomes a borrow, so a later move or store of `x` is a checker error unless the source writes `.clone()`. Count how many of the 456 fixtures hit this before building more.
- A borrow from a temporary moves a part out of the dying temporary; it needs field-granular drop support, which the prototype must show (the oracle's `owned_borrows` copies at the call).
- Closures, interface views (`ret_view`) and function values never borrow (reference-ownership non-goals).

## Alternatives considered

- Do nothing: the flag stays off and lowering keeps copying siborrowedly, which the owner rule forbids.
- A second, separate fixpoint in lowering: rejected, it can disagree with the checker.
- Require `.clone()` at every `return b` of a borrowed parameter: contradicts the approved reference-ownership design and breaks code the oracle accepts (`borrow-whole-temporary.ms`).
- Keep the clone and only hide it from the error: violates the rule.

## Touched components

`own/` (new `borrowing callables.c`, facts column), `check/facts.h` (the bit), `lower/lower_func.c`, `lower_expr.c`, `lower_call.c` (return and call binding), `own/borrows.c` (reads the fact). `mir/`: none expected.

## Testing

Check, run and test sweeps against a same-main baseline (no new failures); the 456 fixtures stop failing at the flip; MIR verify stays clean (`ret: %v is owned, but this function borrows`). Fixtures: `borrow-whole-temporary.ms`, `borrowed-container-reads.ms`, `borrowed-helper-loop.ms`.
