# Wrapped and converted results are views of their arguments

## Summary

- Problem: a lent part that leaves a function wrapped (`return ok(r.name)`, `return r.tags[0]` as `String?`, `try f(r)` passing a lent error on) or that is bound wrapped (`let o: Item? = item`) is a move, so callers clone to keep the original. #2199 added 70 `.clone()` calls for the shapes one-owner semantics rejects, and the user rejects both the clones and compiler-inserted copies.
- Change: wrapping a lent value into `Optional` or `Result` keeps it a reference. The checker records the wrapper (`view_wraps`); lowering builds it with `opt.view` or a new `alt.view`, which neither retain nor release their payload, and the function lends as if unwrapped. Nothing changes at runtime: no tag, no new drop path.
- Stage 2 (interface views): converting a borrowed value to an interface (`return cause` as `Error`, `error(cause)` as `Int!`, `let e: Error = cause`, a widened lending call, `try` of one) builds a view: a box of the leaves as they are, with the vtable word tagged so dropping it frees only the box. Such a function is a *view lender*: its result is owned and dropped by the caller, and points into the arguments, which the caller holds borrowed while it lives.
- Not changed: a plain lent path beside a new value stays an error; stores, captures and interface implementations keep `.clone()`; `Result` widening of a non-interface payload copies it.

## Status

Implemented in this PR, 2026-11-01, checked against `23477392`. Direction (Chinmay, 2026-11-01): "i cannot pass the variable deep without clone? ... that doesnt make sense"; "the pr seems to be adding clone to more places, which is the opposite intent"; "no i don't want implicit copying". Reverses the clause of `reference-ownership.md` (Results) and `crates/ms-check/OWNERSHIP.md` that a value converted to `Optional` or `Result` on the way out is owned. Skeptical review verdict (subagent, 2026-11-01): revise; ship `Optional`/`Result` views, drop mixed-return views, defer interface views until specified (see Alternatives and Open questions). Stage 1 merged as #2210.

Stage 2 (interface views), 2026-11-01, on `04634b78`. Direction (Chinmay): "i see yeah tagging makes sense, let's do it, save on clones!" after asking why interfaces need clones. Adversarial review (subagent, 2026-11-01, 41 programs under valgrind, Debug and Release): two holes found and closed before this PR, both a view local handed on without the checker noticing (`let e = first_error(cause); return relay(e)`, `return id(first_error(cause))`; `let e2 = e; return e2`); the rest accepted with correct output or rejected with the expected diagnostic.

## Problem

Measured (`23477392`, the 70 `.clone()` lines #2199 added removed, debug `ms check` over the changed files): 59 rejections in four shapes.

| Shape | Sites | Example |
| --- | --- | --- |
| wrapped or converted on the way out, or at a binding: `ok(inner)`, `try visit(r)`, `return cause` as `Error`, `let view: Counter = tally` | 25 | `tests/conformance/fixtures/e2e/accept/result-argument-inference.ms`, `try-result-payloads.ms`, `tests/e2e/testdata/projects/error_boundaries` |
| lent path next to a new value | 16 | `stdlib/data/toml.ms:1071` `if bare: return key` / `return quote_text(key)` |
| lent value stored or captured: `names.append(first_tag(..))`, `m.add(original, 1)`, `fn() Error: cause` | 15 | `map_add_scope/first.ms:15`, `core_parity/first.ms:54` |
| interface implementation returning a lent value | 3 | `stdlib/collections/ordering.ms:196` `return lesser(self, other)` |

```manuscript
fn named(r: Row) String!Missing:
    return ok(r.name)               # moved `r.name`; callers wrote ok(r.name.clone())

fn tail(result: Row!Bad) String!Bad:
    let row = try relay(result)     # `relay` lends; the try's error path moved it
    return ok(row.name)
```

Lowering already had the first half: `opt.view` lends a container entry as an optional. The checker's move was what made the payload owned.

## Design

A view is a wrapper whose payload belongs to another value. The checker holds the owner borrowed while the view lives, exactly as for the arguments of a lending call; lowering never drops a view.

- Returns. In `returned`, `wrapped_lend(e)` recognizes `x?`-style wrapping (`Info.wrap_some` without an error conversion) and `ok(x)` / `error(x)` (a `Result` constructor with one unlabeled `Move`-class argument). Such an expression lends when its payload does; the node goes into `view_wraps` and the call's constructor arguments are forced to `Borrow`. `lend_source` and `pure_origins` see through the wrapper, so the callers' holds and overlap rules are unchanged.
- `try`. `try_return` treats the implicit error return of `try e` like `return error(err)`: when `e` lends and its error type is `Move`-class, the try lends (and `tail` above lends `result`); when the error is owned, the function owns its result, and a plain lent path beside it is the existing mixed-return error. A `try` whose payload type is `Copy` reads its operand.
- Bindings. `let o: Item? = item`, `let k = ok(x)` and `let v: T? = r.f` bind a shared borrow of the source (`bind`, "binding of a borrowed value"); changing the source while the binding lives is the usual error.
- Withdrawal. A wrapped lend beside a path that returns a new value is withdrawn (`plain_lent` false): the function owns its result and lowering copies the payload as today, so `ok(p.name)` beside `try risky(n)` with an owned error keeps compiling. Only an unwrapped lend beside a new value is an error.
- Lowering. `expr` emits `opt.view` and `construct` emits `alt.view` (`Op::AltView`: Borrow operands, `result_mode` Borrow, verifier rejects a boxed alternative, interpreter shares the fields) when the node is in `view_wraps` and the payload is not owned; `try_expr`'s error path in a `ret_borrowed` function returns `alt.view` of the lent error. Otherwise the previous owned paths run.

### Interface views (stage 2)

An interface value is `{data, vtable}`; `data` is a heap box of the payload's leaves and `vtable` points at `[drop, methods.., copy]`, 8-aligned. The low two bits of the vtable word now say what the value owns: `0` the box and its payload (`iface.new`, drop calls `vtable[0]`), `1` only the box (`iface.lend`, drop frees the box), `2` nothing (`iface.view`, drop does nothing). Dispatch, `iface.is` and `copy` mask the tag; a copy is always tag `0`.

- Lowering. `fit_ty` of a borrowed `Move`-class value emits `iface.lend`: an allocation and a bitwise store of the leaves, no copy of what they point at. A `ret_view` function returning a plain reference of interface type emits `iface.view`. `try` and `Result` widening take the error out of the source alternative (`alt.take`, `alt.release`) instead of copying and dropping it.
- Checker. A conversion of a borrowed `Move`-class value on a return path makes the function a view lender (`Lend.view`, `Func.ret_view`): `lends` and `view` are both set, no path. The caller treats the result as a borrow of the arguments for holds, freezing and overlap (`pure_origins`) and as owned for dropping. A new value beside a view is fine (both owned); a plain reference beside one becomes a view when the result type is an interface and is an error otherwise. `let e: Error = cause`, `let r: Int! = error(cause)` and `let e = first_error(cause)` bind view locals: the binding owns the box and borrows `cause`. Returning a view local by name, or handing it whole to a plain lender that is returned (`return relay(e)`), moves the box out (`view_moves`; lowering takes the local and skips its drop on that path). `let e2 = e` at `e`'s last use hands the box to `e2`; with `e` used later, `e2` is a plain reference into `e`'s box and cannot leave the function. Storing a view local, capturing it in an escaping closure or `var`-binding one is rejected with a `.clone()` remedy.
- Mutating interfaces. An interface with a `var fn` operation (`ReadStream`, `WriteStream`) is converted by copy, as before (`contract_mutates`, checked in `view_source` and `fit_ty`): natives such as `copy` call its operations on the box, and a write into a box of borrowed leaves would free the owner's value and leak the new one (`make leak-check` caught `io-generic-streams.ms` writing into a `Mem` sink through a view). A checked `var` call needs `var x: Sink` already, so only natives reach this.
- Optimizer. `Module::result_views` names the instructions whose owned result may point into other registers (`iface.lend`, `iface.view`, calls to `ret_view` functions); `lastuse` keeps their sources alive and `copyelim` neither moves nor takes from a register tainted by one.

| Before (`23477392`) | After |
| --- | --- |
| `let outer: Result[Int!Failure, Tagged[Int]] = ok(inner.clone())` | `ok(inner)`; `outer` borrows `inner` |
| `let value = try visit(result, var visits).clone()` | `try visit(result, var visits)`; `visit` lends `result` and the error passes through |
| `fn first_error(cause: Cause) Error: return cause.clone()` | `return cause`; the result is a view of `cause` |
| `l.accounts.get(id).get().clone()` returned as an interface | `l.accounts.get(id).get()`; 18 `.clone()` lines removed from fixtures and the bank-ledger reference solution |

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/ownership/{walk,mod}.rs`, `checker.rs`, `lib.rs` | `wrapped_lend`, `result_payload`, `try_return`, `plain_lent` withdrawal, `view_wraps` facts | `tests/ownership/accept/wrapped_lends.ms`, `reject/wrapped_lend_held.ms` |
| `crates/ms-mir` (`ir.rs`, `builder.rs`, `verify.rs`, `interp.rs`) | `Op::AltView` | `cargo test -p ms-mir`, verifier rule |
| `crates/ms-clif/src/lower.rs` | `AltView` lowers like `AltNew` | `make count-check`, `make leak-check`, valgrind on the e2e fixture, Debug and Release |
| `crates/ms-lower` (`cx.rs`, `expr.rs`, `call.rs`, `matching.rs`) | view ops where `view_wraps` says so | `tests/e2e/testdata/accept/wrapped-lends.ms`, conformance `e2e/accept/wrapped-lends` |
| fixtures | 12 `.clone()` removed (`result-argument-inference.ms`, `try-result-payloads.ms`) | `make conform`, `make e2e` |
| `OWNERSHIP.md`, `crates/DESIGN.md`, `references.md`, wiki | the wrapping rule and what still clones | `make docs-check`, `make repo-check` |
| `crates/ms-mir` (`ir.rs`, `builder.rs`, `verify.rs`, `interp.rs`, `opt/{copyelim,lastuse}.rs`) | `Op::IfaceLend`, `Op::IfaceView`, `Func.ret_view`, `result_views`, view taint | `cargo test -p ms-mir`, `make count-check` |
| `crates/ms-clif/src/lower.rs` | tagged vtable word: drop by tag, masked dispatch, `iface.is` and copy | `make leak-check`, valgrind on the review programs, Debug and Release |
| `crates/ms-check/src/ownership/{walk,mod,modes}.rs` | view lenders, view locals, view moves, rebinding rule | `tests/ownership/accept/interface_views.ms`, `reject/interface_view_held.ms` |
| `crates/ms-lower` (`iface.rs`, `func.rs`, `expr.rs`, `stmt.rs`, `matching.rs`) | `iface.lend` in `fit_ty`, `iface.view` returns, `view_moves` takes, `alt.take` in `try` | `tests/e2e/testdata/accept/interface-views.ms`, conformance `e2e/accept/interface-views` |

## Alternatives

- Do nothing: the clones stay; the user rejected this ("opposite intent").
- Compiler-inserted copies at these sites: zero diagnostics, hidden allocations; rejected ("no i don't want implicit copying").
- Mixed returns as runtime-tagged views (prototyped: a `view` op, string `STR_VIEW` tag, `Lend.view` making lowering return owned values): covers the 16 stdlib/tools sites, but `Own`-mode results that hide views break `copyelim`, `lastuse` and `strfuse` and `try` on such a result dangles, and the result's callers then store a value that borrows the arguments, so `parts.append(inline_value(item))` needed `.clone()` where the callee arm had one before. It moves clones to callers instead of removing them. Rejected.
- Records of scalars copy like scalars: `reference-ownership.md` reversed exactly this rule for uniformity.
- Report instead of withdraw a wrapped lend beside an owned path: breaks existing code that mixes `ok(p.name)` with `try risky(n)`; withdrawal keeps `main`'s behaviour there.
- Interfaces as unboxed fat pointers (`data` pointing at the caller's storage, no box): a converted parameter's leaves live in registers in the callee, and a result must outlive the callee's frame, so a lent return still needs a heap box; the tag is what lets one representation serve owned and borrowed payloads. The box per conversion is the cost `iface.new` already paid, minus the copy.
- Interfaces erased to generic bounds only (no `List[Shape]`, no `Error` values): a language change the user did not ask for; a generic bound already monomorphizes and copies nothing.

## Open questions

- A view local of a non-interface type (`let r: Int! = error(cause)`) returned by name is copied, not moved: moving it needs a per-type "owns nothing" form of the alternative. `.clone()`-free, but one copy.
- `let e: Error = if c: a else: b` consumes both operands (the conditional is not a place); `var e = first_error(cause)` is rejected, since a `var` through a view could replace the box while it is borrowed. Both keep `.clone()`.
- `Result` widening of a borrowed result copies the `ok` payload (`fn f(r: Row) String!: return g(r)` with `g` lending `String!Bad`): the view lender's result is owned, and only interfaces have a view form. Same as before this change.
- Closures returning a capture (`fn() Error: cause`): a sound rule needs the result of calling any `fn` value to hold that value, which would force `.clone()` in `out.append(transform(x))`-shaped code. Keep `.clone()`.
- Storing a lent value (`m.add(original, 1)`, `Box(v: a)`): the store outlives the source, so the copy is intentional. Keep `.clone()`.
