# Owned arguments through dynamic calls

## Summary

- Problem: `move` on a function-type parameter or an interface operation is enforced by the checker only. The call through a function value or interface still lends the argument; a callee that keeps it copies it, and the caller drops the original. A resource cannot be copied, so the checker rejects keeping it, and a method value of a `fn move` method copies its receiver on every call.
- Change: a `move` parameter of a function type or interface operation is passed owned at run time. The MIR function type and interface method signature carry which parameters move; every closure and vtable entry takes those parameters owned; callers hand them over.
- Decision requested: none (Chinmay, 2026-11-17: "please do it properly"). The method-value rule below changes accepted programs.

## Status

Implemented 2026-11-18 (checked at `52ee712d`). Follows [declared move mode](declared-move-mode.md) stage 3, whose Status listed these two gaps. Found on the way and fixed: a declared `move` resource parameter the body only reads was never closed (`consumed_param_resources` tracked only inferred moves). Follow-up (2026-11-18): the borrowed instance is gone. The checker rejects a text, comparison, hash or JSON method that keeps what the language lends it, and an interface conversion whose method keeps a receiver the operation lends, so every caller hands over what an instance keeps. A `move fn` operation called through an interface now takes the receiver too: the caller hands over the interface value, the table entry moves the payload out of its box, and the caller frees the empty box. The checker rejects moving a view of a borrowed value, so no copy remains.

## Problem

Verified in source:

- `lower_ty_uncached` (`ms-lower/src/cx.rs:631`) lowers `fn(move T) U` and `fn(T) U` to the same `TyKind::Fn(params, ret)`; `MethodSig` (`ms-mir/src/types.rs:522`) has no modes. `verify::arg_modes` gives `CallInd` and `CallMethod` borrowed arguments.
- Every closure and vtable entry is built with `Mode::Borrow` parameters: lambdas (`closure.rs` `lower_lambda_body`, which binds a parameter borrowed and copies it if kept, `boundary_reads`), named-function and native thunks, interface method-value thunks, adapters (`make_fn_adapter`, which also copies into a lifted optional parameter), `bound_alias.rs`, runtime-called closures (`external.rs`, `fswalk.rs`, `httpserve.rs`, `runner.rs`) and vtable entries (`iface.rs` `vtable_for`, `iface_native_thunk`): about 19 constructors. `owned_mask` (`func.rs:281`) says "every call through a function value or interface uses the borrowed signature"; a function that keeps a parameter gets a second, borrowed instance (`adapter`, `func.rs:2057`) whose copies are that adaptation. The copies are real: `copyelim` removes only copies feeding reads, and a kept argument is stored.
- Type identity: `tytable::walk` (`ms-check/src/tytable.rs:180`) flags `var` and lifted parameters of a function type but not `move`, so `fn(move T)` and `fn(T)` share a lowered type and a `shape()` key.
- The interpreter (`interp/control.rs:182`) treats `CallInd` and `CallMethod` arguments as borrowed.
- The checker covers the gap with copies: `move_out` on a lambda parameter rejects a resource ("a function value only borrows its arguments") and otherwise records a copy (`require_clonable`, `walk/exprs.rs:566`). A method value whose method moves its receiver, declared or inferred (`walk/stmts.rs:714`, fixture `method-value-of-a-consuming-method-cannot-own-a-resource.ms`), "keeps its receiver for repeated calls", so it clones per call; so does an `Optional`/`Result` combinator value (`wrapper_passthrough`, `:704`).
- Observable: `apply(fn move x: files.append(x), file)` with `file` a resource is rejected; a `Sink` implementation that stores a written resource is rejected; `f := opt.or_else; f(a); f(b)` copies `opt` twice.

## Design

- Types: `tytable` gains a MOVE parameter flag (the child index shrinks to 29 bits), so `fn(move T)` is its own type everywhere, including `shape()`.
- MIR: `TyKind::Fn` gains a bit set of parameters passed owned; `MethodSig` gains the same. `arg_modes` and the interpreter read them for `CallInd` and `CallMethod`, so elaboration, unwinding and copy elimination treat those arguments as moved into the call. The verifier checks that a `ClosureNew` target declares `Mode::Move` exactly at those positions. MIR text writes `fn(move T) -> U`.
- Lowering: `lower_ty` sets the bits from `Param.moving`; interface signatures from the operation's `move`. One helper builds a closure's parameter list from its function type, used by every constructor. A lambda binds a `move` parameter as an owned local. A thunk or vtable entry forwarding to a named function passes an owned argument to the function's owned instance when the function keeps it, and otherwise lends it and lets elaboration drop it. A native satisfying a `move` operation gets its argument the same way. Function values, interfaces and the test and bench drivers no longer reach the borrowed `adapter` instance; it remains only for the compiler's own lending callers (formatting, JSON and arithmetic hooks).
- Callers: a function-value or interface call evaluates a `move` argument as an owned value (the checker already moved it). Natives that run a `fn(move T)` callback (`Optional`/`Result` combinators) hand the payload over (`opt.unbox`, `alt.take`), and always receive a fitted function: a borrowing function passed there gets the existing adapter, which takes the argument owned, lends it and drops it (one adapter per such `opt.map(named_fn)`, instead of a branch per call). A lifted optional parameter wraps the owned argument instead of copying it.
- Checker: a lambda parameter under `move` is owned like a declared `move` parameter, so it may move a resource. A method value whose method moves its receiver, declared or inferred, is rejected with the closure that writes `.clone()` as the remedy; no hidden receiver copy remains.

## Evidence

Deleted: the lambda-parameter resource rejection and copy rule, the method-value receiver clones, the copies the borrowed `adapter` instance made for every function value, interface entry and test or bench driver, the lifted-parameter copy, and the "borrowed signature" exception. Gained: resources through `move` callbacks and interface operations (`res.map(fn f: Wrap(f))` with a resource payload, a `Sink` of resources). Reach is narrow today (7 `Optional`/`Result` combinators, `Sink.write`, `Transform.step`, `Transport.write`, `HttpExchange.write`), but every user `move` callback and interface operation gets it.

## Alternatives

- Do nothing: `move` keeps meaning "copied" through dynamic calls; resources stay rejected there.
- Pass every closure argument owned: one convention, but each borrowing callback (`List.map`) would copy its element to hand it over.
- A per-call mask on `CallInd` instead of the type: the closure would not know its own convention; the type is where both sides meet.

## Stages

One PR: MIR, lowering, checker, tests (`ms-mir` verifier cases, ownership corpus, e2e fixtures for a resource through a `move` callback and a `move` interface operation), docs.

## Review

Skeptic review (2026-11-17) found the type-identity gap, the interpreter, unadapted natives, the lifted copy, the borrowed `adapter` instance, the inferred-move method values and nine more constructors; all are folded in above. Do nothing loses: the copies are real, and resources are rejected.

## Open questions

- A method value of a consuming method: reject (chosen) or allow exactly one call. A closure states the copy; no stdlib or fixture binds a `fn move` method as a value.
